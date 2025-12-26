// ===== MAIN.JS - Initialization and Event Listeners =====
//
// This module handles:
// - Page initialization
// - Event listener setup
// - Excel file upload
// - Save/load game system
// - Tutorial and UI controls
// - Integration of all other modules

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

  console.log('Initialization complete');
});

// ===== SAVE/LOAD SYSTEM =====

function loadState() {
  const savedState = localStorage.getItem('roguelikeState');
  if (savedState) {
    const state = JSON.parse(savedState);
    rations = state.rations;
    gold = state.gold || 0;
    health = state.health;
    maxHealth = state.maxHealth || 10;
    inventory = state.inventory;
    beatenGames = state.beatenGames;
    selectedPhase2Games = state.selectedPhase2Games;
    excludedGames = state.excludedGames || [];
    roguePoints = state.roguePoints;
    pactConditions = state.pactConditions;
    startGame = state.startGame;
    amuletGame = state.amuletGame;
    encounterHistory = state.encounterHistory || [];
    markedSvg = state.markedSvg;

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
    discovery: discovery
  };

  localStorage.setItem('roguelikeGameSaves', JSON.stringify(gameSaves));
  console.log('Game saved:', gameState.saveName);
}

function loadSavedGame(saveName) {
  const save = gameSaves[saveName];
  if (!save) return;

  // Restore game state
  gameState = { ...save };
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

document.getElementById('new-game-btn')?.addEventListener('click', () => {
  console.log('=== START RUN CLICKED ===');
  console.log('games.length:', games.length);
  console.log('PLAYER_CHARACTERS keys:', Object.keys(PLAYER_CHARACTERS));

  if (games.length === 0) {
    alert('Game data is still loading... Please wait a moment and try again.');
    return;
  }

  // Populate character selection
  const charSelection = document.getElementById('character-selection');
  charSelection.innerHTML = '';

  console.log('Populating character selection...');
  for (const [id, char] of Object.entries(PLAYER_CHARACTERS)) {
    console.log(`  - Adding character: ${id} (${char.name})`);

    const charDiv = document.createElement('div');
    charDiv.className = 'character-option';
    charDiv.dataset.charId = id;
    charDiv.style.cssText = `
      padding: 15px;
      background: #3d3d3d;
      border: 3px solid #555;
      border-radius: 8px;
      cursor: pointer;
      text-align: center;
      transition: all 0.2s;
    `;

    charDiv.innerHTML = `
      <img src="${char.icon}" style="width: 64px; height: 64px; image-rendering: pixelated; margin-bottom: 10px;">
      <div style="font-weight: bold; margin-bottom: 5px;">${char.name}</div>
      <div style="font-size: 11px; color: #aaa; margin-bottom: 8px;">${char.description}</div>
      <div style="font-size: 10px; color: #888;">
        STR:${char.startingStats.strength}
        DEX:${char.startingStats.dexterity}
        INT:${char.startingStats.intelligence}
        CHA:${char.startingStats.charisma}
      </div>
    `;

    charDiv.onclick = () => {
      document.querySelectorAll('.character-option').forEach(opt => {
        opt.style.border = '3px solid #4a4440';
      });
      charDiv.style.border = '3px solid #ffcc66';
      selectedCharacter = id;
    };

    charSelection.appendChild(charDiv);
  }

  document.getElementById('save-modal').style.display = 'flex';
});

document.getElementById('cancel-save')?.addEventListener('click', () => {
  document.getElementById('save-modal').style.display = 'none';
});

document.getElementById('confirm-save')?.addEventListener('click', () => {
  const saveName = document.getElementById('save-name-input').value.trim();
  if (!saveName) {
    alert('Please enter a save name');
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
  strength = character.startingStats.strength;
  dexterity = character.startingStats.dexterity;
  intelligence = character.startingStats.intelligence;
  charisma = character.startingStats.charisma;
  reroll = character.startingStats.reroll || 0;
  dash = character.startingStats.dash || 0;
  skip = character.startingStats.skip || 0;
  discovery = character.startingStats.discovery || 0;

  // Reset health and gold for new run
  health = 10;
  maxHealth = 10;
  gold = 0;

  // Clear inventory and curses for new run
  inventory = [];

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
    strength: strength,
    dexterity: dexterity,
    intelligence: intelligence,
    charisma: charisma,
    escapePhase: false,
    escapeGames: [],
    escapeProgress: 0,
    gameStatusEffects: {} // Map of game names to arrays of status effects
  };

  startGame = start;
  amuletGame = amulet;

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

document.getElementById('return-menu')?.addEventListener('click', () => {
  if (confirm('Return to main menu? (Game will be saved)')) {
    saveCurrentGame();
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

// ===== MODAL FUNCTIONS =====

function createGameModal(content) {
  const existingModal = document.getElementById('game-modal');
  if (existingModal) existingModal.remove();

  const modal = document.createElement('div');
  modal.id = 'game-modal';
  modal.style.cssText = `
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0,0,0,0.95);
    display: flex;
    justify-content: center;
    align-items: center;
    z-index: 10000;
    animation: fadeIn 0.3s;
  `;

  const modalContent = document.createElement('div');
  modalContent.className = 'modal-content';
  modalContent.style.cssText = `
    background: #2a2420;
    padding: 30px;
    border-radius: 12px;
    max-width: 800px;
    max-height: 90vh;
    overflow-y: auto;
    color: #e6d5b8;
    box-shadow: 0 10px 40px rgba(0,0,0,0.8);
    border: 2px solid #cc6600;
  `;

  modalContent.innerHTML = content;
  modal.appendChild(modalContent);
  document.body.appendChild(modal);

  return modal;
}

function closeGameModal() {
  const modal = document.getElementById('game-modal');
  if (modal) {
    modal.style.animation = 'fadeOut 0.3s';
    setTimeout(() => modal.remove(), 300);
  }
}

function showCombatModal() {
  if (enemies.length === 0) return;

  // Set phase to combat
  gameState.phase = 'combat';
  updateInventory(); // Refresh item UI to update usable item buttons

  // Determine stat based on current game type
  const currentGameObj = games.find(g => g.name === gameState.currentGame);
  let requiredStat = 'Strength'; // Default

  if (currentGameObj) {
    const gameType = currentGameObj.type.toLowerCase();
    switch(gameType) {
      case 'action': requiredStat = 'Strength'; break;
      case 'deckbuilding': requiredStat = 'Charisma'; break;
      case 'strategy': requiredStat = 'Intelligence'; break;
      case 'traditional': requiredStat = 'Dexterity'; break;
      default: requiredStat = 'Strength';
    }
  }

  // Difficulty scales with distance (visitedGames.length)
  const distance = gameState.visitedGames?.length || 0;
  let powerText = 'Low';
  if (distance >= 10) {
    powerText = 'High';
  } else if (distance >= 5) {
    powerText = 'Medium';
  }

  const matchingEnemies = enemies.filter(enemy =>
    enemy.powerLevel === powerText && enemy.stat === requiredStat
  );

  if (matchingEnemies.length === 0) return;

  const randomIndex = Math.floor(Math.random() * matchingEnemies.length);
  const enemy = matchingEnemies[randomIndex];

  // Get player's stat value for this check
  let playerStatValue = 0;
  switch(enemy.stat) {
    case 'Strength': playerStatValue = strength; break;
    case 'Dexterity': playerStatValue = dexterity; break;
    case 'Intelligence': playerStatValue = intelligence; break;
    case 'Charisma': playerStatValue = charisma; break;
  }

  createGameModal(`
    <div style="text-align: center;">
      <h2 style="color: #ff4444; margin-top: 0;">Combat Encounter!</h2>
      <h3>${enemy.name}</h3>
      <p style="color: #888;">From: ${enemy.game}</p>
      ${enemy.imageUrl ? `<img src="${enemy.imageUrl}" style="max-width: 200px; max-height: 200px; image-rendering: pixelated; margin: 10px auto; display: block;" alt="${enemy.name}">` : ''}
      <div style="background: rgba(0,0,0,0.3); padding: 15px; border-radius: 8px; margin: 15px 0;">
        <p style="font-size: 18px; margin: 5px 0;">
          <span style="color: ${getStatColor(enemy.stat)};">${enemy.stat}</span> Check:
          <strong>Roll ${enemy.rollCheck}+</strong>
        </p>
        <p style="font-size: 16px; margin: 5px 0; color: #aaa;">
          Your ${enemy.stat}: <strong style="color: ${getStatColor(enemy.stat)};">+${playerStatValue}</strong>
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
    if (gameState && gameState.activeCurses) {
      const weaknessCurses = gameState.activeCurses.filter(c => c.name.toLowerCase().includes('weakness'));
      if (weaknessCurses.length > 0) {
        // Use only the first weakness curse and remove it
        const weaknessCurse = weaknessCurses[0];
        let penalty = 0;
        if (weaknessCurse.power === 'Low') penalty = 2;
        else if (weaknessCurse.power === 'Medium') penalty = 3;
        else if (weaknessCurse.power === 'High') penalty = 4;

        cursePenalty = penalty;
        curseMessages.push(`Curse of Weakness: -${penalty}`);

        // Remove this specific curse instance after this roll
        const curseIndex = gameState.activeCurses.indexOf(weaknessCurse);
        gameState.activeCurses.splice(curseIndex, 1);

        if (typeof updateCursesDisplay === 'function') {
          updateCursesDisplay();
        }
        if (typeof updateActiveCursesList === 'function') {
          updateActiveCursesList();
        }
      }
    }

    // Check for Curse of Failure (damage on rolling 1) - handle stacking
    if (diceRoll === 1 && gameState && gameState.activeCurses) {
      const failureCurses = gameState.activeCurses.filter(c => c.name.toLowerCase().includes('failure'));
      if (failureCurses.length > 0) {
        // Trigger all failure curses if rolled a 1
        let totalDamage = 0;
        failureCurses.forEach(failureCurse => {
          let damage = 0;
          if (failureCurse.power === 'Low') damage = 2;
          else if (failureCurse.power === 'Medium') damage = 3;
          else if (failureCurse.power === 'High') damage = 4;
          totalDamage += damage;
        });

        health = Math.max(0, health - totalDamage);
        gameState.health = health;
        if (typeof updateTopBar === 'function') {
          updateTopBar();
        }

        curseMessages.push(`Curse of Failure (×${failureCurses.length}): -${totalDamage} HP!`);

        // Show popup notification for Curse of Failure damage
        setTimeout(() => {
          if (typeof createGameModal === 'function') {
            createGameModal(`
              <div style="text-align: center;">
                <h2 style="color: #ff4444; margin-top: 0; font-size: 32px;">😱 Curse of Failure!</h2>
                <p style="font-size: 18px; color: #ff8888;">You rolled a natural 1!</p>
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
          }
        }, 500);

        // Remove all failure curses after triggering
        gameState.activeCurses = gameState.activeCurses.filter(c => !c.name.toLowerCase().includes('failure'));
        if (typeof updateCursesDisplay === 'function') {
          updateCursesDisplay();
        }
        if (typeof updateActiveCursesList === 'function') {
          updateActiveCursesList();
        }

        // Check for death
        if (health <= 0) {
          // Will be handled by the death check below
        }
      }
    }

    const totalRoll = diceRoll + playerStatValue - cursePenalty;
    const success = totalRoll >= enemy.rollCheck;

    let resultHTML = `
      <div style="background: rgba(0,0,0,0.3); padding: 15px; border-radius: 8px; margin: 10px 0;">
        <p style="font-size: 20px; font-weight: bold;">Dice: ${diceRoll}</p>
        <p style="font-size: 16px; color: ${getStatColor(enemy.stat)};">+ ${enemy.stat} Bonus: ${playerStatValue}</p>
        ${cursePenalty > 0 ? `<p style="font-size: 16px; color: #ff6666;">- Weakness Penalty: ${cursePenalty}</p>` : ''}
        <p style="font-size: 24px; font-weight: bold; margin-top: 10px; color: gold;">Total: ${totalRoll}</p>
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
            document.getElementById('dungeon-screen').style.display = 'none';
            document.getElementById('main-menu').style.display = 'flex';
          };

          document.getElementById('death-retry-btn').onclick = () => {
            closeGameModal();
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

function showEventModal() {
  if (events.length === 0) return;

  // Set phase to event
  gameState.phase = 'event';
  updateInventory(); // Refresh item UI to update usable item buttons

  const randomIndex = Math.floor(Math.random() * events.length);
  const event = events[randomIndex];

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

  const modal = document.getElementById('game-modal');
  if (modal) {
    modal.querySelector('.modal-content').innerHTML = `
      <div style="text-align: center;">
        <h2 style="color: #4CAF50; margin-top: 0;">Choice Made</h2>
        <p style="font-size: 18px;">${option}</p>
        <p style="color: #888; margin-top: 20px;">The consequences of your choice unfold...</p>
        <button onclick="closeGameModal()" style="padding: 10px 20px; margin-top: 20px; background: #4CAF50; border: none; border-radius: 6px; color: white; cursor: pointer;">Continue</button>
      </div>
    `;
  }
  saveCurrentGame();
}

function showShopModal(purchasedIndices = []) {
  if (items.length === 0) return;

  // Set phase to shop
  gameState.phase = 'shop';
  updateInventory(); // Refresh item UI to update usable item buttons

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

      const rarityItems = items.filter(item => item.rarity === targetRarity);
      if (rarityItems.length > 0) {
        const randomIndex = Math.floor(Math.random() * rarityItems.length);
        selectedItem = rarityItems[randomIndex];
      } else {
        // Fallback to any item if no items of target rarity
        const randomIndex = Math.floor(Math.random() * items.length);
        selectedItem = items[randomIndex];
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
  let frugalityModifier = 0;
  let hasFrugality = false;
  if (gameState && gameState.activeCurses) {
    const frugalityCurses = gameState.activeCurses.filter(c => c.name.toLowerCase().includes('frugality'));
    if (frugalityCurses.length > 0) {
      hasFrugality = true;
      // Sum all frugality penalties
      frugalityCurses.forEach(curse => {
        if (curse.power === 'Low') frugalityModifier += 5;
        else if (curse.power === 'Medium') frugalityModifier += 10;
        else if (curse.power === 'High') frugalityModifier += 15;
      });
    }
  }

  let itemsHTML = '<div style="display: flex; flex-direction: column; gap: 15px; margin-top: 20px;">';

  shopItems.forEach((item, index) => {
    const isPurchased = purchasedIndices.includes(index);
    const basePrice = item.rarity === 'common' ? 10 : item.rarity === 'uncommon' ? 25 : 50;
    const price = basePrice + frugalityModifier;
    const rarityColor = item.rarity === 'common' ? '#aaa' : item.rarity === 'uncommon' ? '#4CAF50' : '#9b59b6';

    let priceDisplay = '';
    if (hasFrugality) {
      priceDisplay = `
        <span style="color: gold; font-weight: bold;">
          <span style="text-decoration: line-through; color: #888; margin-right: 8px;">${basePrice}</span>
          ${price} Gold
        </span>
      `;
    } else {
      priceDisplay = `<span style="color: gold; font-weight: bold;">${price} Gold</span>`;
    }

    itemsHTML += `
      <div style="padding: 15px; background: #2d2d2d; border-radius: 8px; border: 2px solid ${rarityColor};">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
          <strong style="font-size: 18px;">${item.name}</strong>
          <span style="color: ${rarityColor}; font-size: 14px;">${item.rarity}</span>
        </div>
        <p style="color: #ccc; margin: 10px 0;">${item.description}</p>
        <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 10px;">
          ${priceDisplay}
          <button class="shop-buy-btn" data-index="${index}" data-price="${price}" style="
            padding: 8px 16px;
            background: ${isPurchased ? '#555' : '#4CAF50'};
            border: none;
            border-radius: 6px;
            color: white;
            cursor: ${isPurchased ? 'not-allowed' : 'pointer'};
          " ${gold < price || isPurchased ? 'disabled' : ''}>
            ${isPurchased ? 'Purchased!' : (gold >= price ? 'Buy' : 'Too Expensive')}
          </button>
        </div>
      </div>
    `;
  });

  itemsHTML += '</div>';

  createGameModal(`
    <div>
      <h2 style="color: gold; margin-top: 0;">Shop Encounter!</h2>
      <p style="text-align: center;">A mysterious merchant appears...</p>
      <p style="text-align: center; color: gold; font-weight: bold;">Your Gold: ${gold}</p>
      ${itemsHTML}
      <button onclick="closeGameModal()" style="width: 100%; padding: 12px; margin-top: 20px; background: #666; border: none; border-radius: 6px; color: white; cursor: pointer;">Leave Shop</button>
    </div>
  `);

  document.querySelectorAll('.shop-buy-btn').forEach(btn => {
    btn.onclick = (e) => {
      const itemIndex = parseInt(e.target.dataset.index);
      const price = parseInt(e.target.dataset.price);
      const item = shopItems[itemIndex];

      if (gold >= price) {
        gold -= price;
        gameState.gold = gold;
        acquireItem(item);

        // Track purchased items
        purchasedIndices.push(itemIndex);

        // Check for Curse of Frugality and remove only ONE after first purchase
        let curseWasRemoved = false;
        if (gameState && gameState.activeCurses) {
          const frugalityCurses = gameState.activeCurses.filter(c => c.name.toLowerCase().includes('frugality'));
          if (frugalityCurses.length > 0) {
            // Remove only the first frugality curse
            const curseIndex = gameState.activeCurses.indexOf(frugalityCurses[0]);
            if (curseIndex !== -1) {
              gameState.activeCurses.splice(curseIndex, 1);
              curseWasRemoved = true;
              if (typeof updateCursesDisplay === 'function') {
                updateCursesDisplay();
              }
              if (typeof updateActiveCursesList === 'function') {
                updateActiveCursesList();
              }
            }
          }
        }

        saveCurrentGame();

        // If curse was removed, refresh the shop to show normal prices
        if (curseWasRemoved) {
          setTimeout(() => {
            showShopModal(purchasedIndices);
          }, 100);
        } else {
          // Otherwise just update button state
          e.target.textContent = 'Purchased!';
          e.target.disabled = true;
          e.target.style.background = '#555';
        }
      }
    };
  });
}

// Clear shop items when closing shop modal
const originalCloseGameModal = window.closeGameModal;
window.closeGameModal = function() {
  if (gameState.phase === 'shop') {
    delete gameState.currentShopItems;
    gameState.phase = null;
  }
  if (typeof originalCloseGameModal === 'function') {
    originalCloseGameModal();
  }
};

function showItemChoiceModal() {
  if (items.length === 0) {
    // If no items, just spawn choices
    setTimeout(() => spawnChoices(), 300);
    return;
  }

  const choices = [];
  const maxAttempts = 100; // Prevent infinite loop

  // Number of item choices = discovery stat
  const numChoices = discovery;

  for (let i = 0; i < numChoices; i++) {
    let attempts = 0;
    let selectedItem = null;

    while (attempts < maxAttempts) {
      // Use luck-based rarity selection
      const targetRarity = selectRandomRarity();

      const rarityItems = items.filter(item => item.rarity === targetRarity);
      if (rarityItems.length > 0) {
        const randomIndex = Math.floor(Math.random() * rarityItems.length);
        selectedItem = rarityItems[randomIndex];
      } else {
        const randomIndex = Math.floor(Math.random() * items.length);
        selectedItem = items[randomIndex];
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
        ${item.image ? `<img src="${item.image}" style="width: 100px; height: 100px; object-fit: cover; image-rendering: pixelated; margin: 0 auto 15px; display: block; border-radius: 8px; border: 2px solid ${rarityColor};" alt="${item.name}" onerror="this.style.display='none';">` : ''}
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
      <h2 style="color: #f39c12; margin-top: 0; text-align: center;">🎁 Choose Your Reward!</h2>
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

      // Now spawn the next choices
      setTimeout(() => spawnChoices(), 300);
    };
  });

  // Add reroll button event listener
  const itemRerollBtn = document.getElementById('item-reroll-btn');
  if (itemRerollBtn && reroll > 0) {
    itemRerollBtn.onclick = () => {
      if (confirm('Reroll item choices?')) {
        reroll--;
        closeGameModal();
        setTimeout(() => showItemChoiceModal(), 100);
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

      // Spawn choices without acquiring an item
      setTimeout(() => spawnChoices(), 300);
    };
  }
}

// ===== ESCAPE PHASE =====

function startEscapePhase() {
  gameState.escapePhase = true;
  gameState.phase = 'escape';
  gameState.escapeGames = [];
  gameState.escapeProgress = 0;

  // Get unique visited games (excluding the amulet game itself)
  const visitedGames = [...new Set(gameState.visitedGames)].filter(g => g !== gameState.amuletGame.name);

  let selectionHTML = '<div style="display: flex; flex-wrap: wrap; gap: 15px; justify-content: center; margin-top: 20px;">';

  visitedGames.forEach((gameName, index) => {
    selectionHTML += `
      <div class="escape-game-option" data-game="${gameName}" style="
        position: relative;
        width: 150px;
        padding: 15px;
        background: #2d2d2d;
        border: 3px solid #666;
        border-radius: 8px;
        cursor: pointer;
        text-align: center;
        transition: all 0.2s;
      ">
        <div class="selection-number" style="
          position: absolute;
          top: -10px;
          right: -10px;
          width: 30px;
          height: 30px;
          background: gold;
          color: #000;
          border-radius: 50%;
          display: none;
          align-items: center;
          justify-content: center;
          font-weight: bold;
          font-size: 16px;
          border: 2px solid #000;
        "></div>
        <div style="font-weight: bold; margin-bottom: 5px;">${gameName}</div>
        <div style="font-size: 11px; color: #888;">Click to select</div>
      </div>
    `;
  });

  selectionHTML += '</div>';
  selectionHTML += '<div style="text-align: center; margin-top: 20px; color: #aaa;">Select 3 games to escape through</div>';
  selectionHTML += '<div id="escape-selected-count" style="text-align: center; margin-top: 10px; font-weight: bold; color: gold;">0 / 3 selected</div>';
  selectionHTML += '<button id="start-escape-btn" disabled style="margin-top: 20px; padding: 12px 30px; background: #4CAF50; border: none; border-radius: 8px; color: white; cursor: pointer; opacity: 0.5;">Begin Escape</button>';

  createGameModal(`
    <div>
      <h2 style="color: gold; margin-top: 0; text-align: center;">🏺 Amulet Acquired!</h2>
      <p style="text-align: center; color: #aaa;">Choose 3 games from your journey to replay as you escape the dungeon.</p>
      <p style="text-align: center; color: #ff4444; font-size: 14px;">Each lost run costs 1 health. Survive to complete your escape!</p>
      ${selectionHTML}
    </div>
  `);

  const selectedGames = [];

  document.querySelectorAll('.escape-game-option').forEach(option => {
    option.onclick = () => {
      const gameName = option.dataset.game;
      const numberDiv = option.querySelector('.selection-number');
      const selectedIndex = selectedGames.indexOf(gameName);

      if (selectedIndex !== -1) {
        // Deselect
        selectedGames.splice(selectedIndex, 1);
        option.style.border = '3px solid #4a4440';
        numberDiv.style.display = 'none';

        // Update numbers for remaining selections
        selectedGames.forEach((g, i) => {
          const opt = document.querySelector(`.escape-game-option[data-game="${g}"]`);
          opt.querySelector('.selection-number').textContent = i + 1;
        });
      } else if (selectedGames.length < 3) {
        // Select
        selectedGames.push(gameName);
        option.style.border = '3px solid #ffcc66';
        numberDiv.style.display = 'flex';
        numberDiv.textContent = selectedGames.length;
      }

      // Update count display
      document.getElementById('escape-selected-count').textContent = `${selectedGames.length} / 3 selected`;

      // Enable/disable start button
      const startBtn = document.getElementById('start-escape-btn');
      if (selectedGames.length === 3) {
        startBtn.disabled = false;
        startBtn.style.opacity = '1';
        startBtn.style.cursor = 'pointer';
      } else {
        startBtn.disabled = true;
        startBtn.style.opacity = '0.5';
        startBtn.style.cursor = 'not-allowed';
      }
    };
  });

  document.getElementById('start-escape-btn').onclick = () => {
    gameState.escapeGames = [...selectedGames];
    gameState.escapePhase = true;
    gameState.escapeProgress = 0;
    if (!gameState.escapeLostRuns) {
      gameState.escapeLostRuns = [0, 0, 0];
    }
    closeGameModal();
    setTimeout(() => showEscapeVisualization(), 100);
  };
}

function showEscapeVisualization() {
  // Remove any existing escape container
  const existingContainer = document.getElementById('escape-container');
  if (existingContainer) {
    existingContainer.remove();
  }

  // Ensure dungeon screen is visible
  const dungeonScreen = document.getElementById('dungeon-screen');
  dungeonScreen.style.display = 'flex';

  // Hide the main dungeon view and show escape view
  document.getElementById('path-viewport').style.display = 'none';
  document.getElementById('target').style.display = 'none';

  // Initialize lost run trackers
  if (!gameState.escapeLostRuns) {
    gameState.escapeLostRuns = [0, 0, 0];
  }

  // Create escape visualization container
  const escapeContainer = document.createElement('div');
  escapeContainer.id = 'escape-container';
  escapeContainer.style.cssText = `
    padding: 40px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 80px;
    min-height: 400px;
    position: relative;
  `;

  // Player icon (left side) - will be moved dynamically
  const playerIcon = document.createElement('img');
  playerIcon.id = 'escape-player-icon';
  playerIcon.src = PLAYER_CHARACTERS[gameState.character].icon;
  playerIcon.style.cssText = `
    position: absolute;
    width: 64px;
    height: 64px;
    image-rendering: pixelated;
    transition: all 0.5s ease;
    z-index: 100;
  `;
  escapeContainer.appendChild(playerIcon);

  const playerDiv = document.createElement('div');
  playerDiv.id = 'escape-player-position';
  playerDiv.style.cssText = 'text-align: center; position: relative;';
  playerDiv.innerHTML = `
    <div style="width: 64px; height: 64px;"></div>
    <div style="font-size: 12px; color: #aaa; margin-top: 5px;">You</div>
  `;
  escapeContainer.appendChild(playerDiv);

  // Escape games
  gameState.escapeGames.forEach((gameName, index) => {
    const gameDiv = document.createElement('div');
    gameDiv.className = 'escape-game-node';
    gameDiv.dataset.index = index;
    gameDiv.style.cssText = `
      text-align: center;
      position: relative;
    `;

    const status = index < gameState.escapeProgress ? 'completed' : index === gameState.escapeProgress ? 'current' : 'upcoming';

    const gameBox = document.createElement('div');
    gameBox.style.cssText = `
      padding: 20px;
      background: ${status === 'completed' ? '#2a2420' : status === 'current' ? 'linear-gradient(145deg, #5a4720, #3f3215)' : '#1a1410'};
      border: 3px solid ${status === 'completed' ? '#4a4440' : status === 'current' ? '#ffcc66' : '#4a4440'};
      border-radius: 12px;
      min-width: 120px;
      opacity: ${status === 'completed' ? '0.6' : '1'};
      color: ${status === 'current' ? '#ffcc66' : '#b8a890'};
    `;
    gameBox.textContent = gameName;
    gameDiv.appendChild(gameBox);

    if (status === 'current') {
      // Lost runs counter
      const lostRunsDiv = document.createElement('div');
      lostRunsDiv.id = `lost-runs-${index}`;
      lostRunsDiv.style.cssText = 'margin-top: 8px; font-size: 12px; color: #ff6644;';
      lostRunsDiv.textContent = `Lost Runs: ${gameState.escapeLostRuns[index]}`;
      gameDiv.appendChild(lostRunsDiv);

      // Lost Run button
      const lostRunBtn = document.createElement('button');
      lostRunBtn.className = 'escape-lost-run-btn';
      lostRunBtn.textContent = 'Lost Run (-1 HP)';
      lostRunBtn.style.cssText = `
        margin-top: 10px;
        padding: 8px 16px;
        background: #ff6644;
        border: none;
        border-radius: 6px;
        color: white;
        cursor: pointer;
        font-weight: bold;
        font-size: 13px;
      `;
      lostRunBtn.onclick = () => recordLostRun(index);
      gameDiv.appendChild(lostRunBtn);

      // Finished button
      const finishBtn = document.createElement('button');
      finishBtn.className = 'escape-finish-btn';
      finishBtn.textContent = 'Finished';
      finishBtn.style.cssText = `
        margin-top: 8px;
        padding: 10px 20px;
        background: #cc6600;
        border: 1px solid #ff8800;
        border-radius: 6px;
        color: white;
        cursor: pointer;
        font-weight: bold;
      `;
      finishBtn.onclick = () => completeEscapeGame(index);
      gameDiv.appendChild(finishBtn);
    }

    escapeContainer.appendChild(gameDiv);
  });

  // Dungeon Exit
  const exitDiv = document.createElement('div');
  exitDiv.style.cssText = 'text-align: center;';
  exitDiv.innerHTML = `
    <div style="
      padding: 30px;
      background: linear-gradient(145deg, #4CAF50, #2E7D32);
      border: 3px solid #4CAF50;
      border-radius: 12px;
      font-weight: bold;
      font-size: 18px;
      color: white;
    ">🚪 EXIT</div>
    <div style="font-size: 12px; color: #aaa; margin-top: 5px;">Freedom</div>
  `;
  escapeContainer.appendChild(exitDiv);

  // Append to the main path viewport container instead of dungeon-screen
  const pathViewportContainer = document.getElementById('path-viewport-container');
  if (pathViewportContainer) {
    pathViewportContainer.appendChild(escapeContainer);
  } else {
    // Fallback to dungeon-screen if container not found
    document.getElementById('dungeon-screen').appendChild(escapeContainer);
  }

  // Position player icon initially
  setTimeout(() => updatePlayerIconPosition(), 100);
}

function updatePlayerIconPosition() {
  const playerIcon = document.getElementById('escape-player-icon');
  if (!playerIcon) return;

  let targetElement;
  if (gameState.escapeProgress >= gameState.escapeGames.length) {
    // Player has completed all games, position at exit
    targetElement = document.querySelector('#escape-container > div:last-child');
  } else if (gameState.escapeProgress === 0) {
    // Position at starting point
    targetElement = document.getElementById('escape-player-position');
  } else {
    // Position at current game
    targetElement = document.querySelector(`.escape-game-node[data-index="${gameState.escapeProgress}"]`);
  }

  if (targetElement) {
    const rect = targetElement.getBoundingClientRect();
    const containerRect = document.getElementById('escape-container').getBoundingClientRect();
    playerIcon.style.left = (rect.left - containerRect.left + rect.width / 2 - 32) + 'px';
    playerIcon.style.top = (rect.top - containerRect.top - 70) + 'px';
  }
}

function recordLostRun(index) {
  // Increment lost run counter
  gameState.escapeLostRuns[index]++;

  // Deduct 1 health
  health = Math.max(0, health - 1);
  gameState.health = health;
  updateHealthDisplay();
  updateGameStats();

  // Update the lost runs display
  const lostRunsDiv = document.getElementById(`lost-runs-${index}`);
  if (lostRunsDiv) {
    lostRunsDiv.textContent = `Lost Runs: ${gameState.escapeLostRuns[index]}`;
  }

  // Check if player died
  if (health <= 0) {
    // Clear items and curses immediately on death
    inventory = [];
    if (gameState.activeCurses) {
      gameState.activeCurses = [];
    }

    createGameModal(`
      <div style="text-align: center;">
        <h1 style="color: #ff4444; font-size: 48px; margin: 20px 0;">💀 YOU ARE DEAD</h1>
        <p style="color: #aaa; font-size: 18px; margin: 10px 0;">You ran out of health during your escape...</p>
        <p style="color: gold; font-size: 16px; margin: 20px 0;">You made it ${gameState.escapeProgress} / ${gameState.escapeGames.length} of the way out with the amulet.</p>
        <div style="margin-top: 30px; display: flex; gap: 15px; justify-content: center;">
          <button id="escape-death-home-btn" style="
            padding: 15px 30px;
            font-size: 18px;
            background: linear-gradient(145deg, #666, #444);
            border: 2px solid #888;
            border-radius: 8px;
            color: white;
            cursor: pointer;
            font-weight: bold;
          ">🏠 Home</button>
          <button id="escape-death-retry-btn" style="
            padding: 15px 30px;
            font-size: 18px;
            background: linear-gradient(145deg, #4CAF50, #2E7D32);
            border: 2px solid #66BB6A;
            border-radius: 8px;
            color: white;
            cursor: pointer;
            font-weight: bold;
          ">🔄 Try Again</button>
        </div>
      </div>
    `);

    // Add event listeners
    setTimeout(() => {
      document.getElementById('escape-death-home-btn').onclick = () => {
        closeGameModal();
        document.getElementById('dungeon-screen').style.display = 'none';
        document.getElementById('main-menu').style.display = 'flex';
      };

      document.getElementById('escape-death-retry-btn').onclick = () => {
        closeGameModal();
        document.getElementById('dungeon-screen').style.display = 'none';
        document.getElementById('main-menu').style.display = 'flex';
        // Trigger new game button click
        setTimeout(() => {
          document.getElementById('new-game-btn')?.click();
        }, 100);
      };
    }, 100);
    return;
  }

  saveCurrentGame();
}

function completeEscapeGame(index) {
  // Progress to next game
  gameState.escapeProgress++;

  // Remove current buttons and counter
  const currentNode = document.querySelector(`.escape-game-node[data-index="${index}"]`);
  const lostRunBtn = currentNode.querySelector('.escape-lost-run-btn');
  const finishBtn = currentNode.querySelector('.escape-finish-btn');
  const lostRunsDiv = currentNode.querySelector(`#lost-runs-${index}`);
  if (lostRunBtn) lostRunBtn.remove();
  if (finishBtn) finishBtn.remove();
  if (lostRunsDiv) lostRunsDiv.remove();

  // Mark as completed
  const gameBox = currentNode.querySelector('div');
  gameBox.style.background = '#2a2420';
  gameBox.style.border = '3px solid #4a4440';
  gameBox.style.opacity = '0.6';

  // Check if all games completed
  if (gameState.escapeProgress >= gameState.escapeGames.length) {
    // Move player to exit
    setTimeout(() => updatePlayerIconPosition(), 100);
    // Victory!
    setTimeout(() => showVictoryScreen(), 800);
  } else {
    // Show buttons on next game
    const nextNode = document.querySelector(`.escape-game-node[data-index="${gameState.escapeProgress}"]`);
    const nextBox = nextNode.querySelector('div');
    nextBox.style.background = 'linear-gradient(145deg, #5a4720, #3f3215)';
    nextBox.style.border = '3px solid #ffcc66';

    // Lost runs counter
    const nextLostRunsDiv = document.createElement('div');
    nextLostRunsDiv.id = `lost-runs-${gameState.escapeProgress}`;
    nextLostRunsDiv.style.cssText = 'margin-top: 8px; font-size: 12px; color: #ff6644;';
    nextLostRunsDiv.textContent = `Lost Runs: ${gameState.escapeLostRuns[gameState.escapeProgress]}`;
    nextNode.appendChild(nextLostRunsDiv);

    // Lost Run button
    const nextLostRunBtn = document.createElement('button');
    nextLostRunBtn.className = 'escape-lost-run-btn';
    nextLostRunBtn.textContent = 'Lost Run (-1 HP)';
    nextLostRunBtn.style.cssText = `
      margin-top: 10px;
      padding: 8px 16px;
      background: #ff6644;
      border: none;
      border-radius: 6px;
      color: white;
      cursor: pointer;
      font-weight: bold;
      font-size: 13px;
    `;
    nextLostRunBtn.onclick = () => recordLostRun(gameState.escapeProgress);
    nextNode.appendChild(nextLostRunBtn);

    // Finished button
    const nextFinishBtn = document.createElement('button');
    nextFinishBtn.className = 'escape-finish-btn';
    nextFinishBtn.textContent = 'Finished';
    nextFinishBtn.style.cssText = `
      margin-top: 8px;
      padding: 10px 20px;
      background: #cc6600;
      border: 1px solid #ff8800;
      border-radius: 6px;
      color: white;
      cursor: pointer;
      font-weight: bold;
    `;
    nextFinishBtn.onclick = () => completeEscapeGame(gameState.escapeProgress);
    nextNode.appendChild(nextFinishBtn);

    // Move player to next game
    setTimeout(() => updatePlayerIconPosition(), 100);
  }

  saveCurrentGame();
}

function showVictoryScreen() {
  const uniqueBeaten = new Set(gameState.visitedGames || []);

  // Save run to history
  saveRunToHistory({
    date: new Date().toISOString(),
    character: PLAYER_CHARACTERS[gameState.character].name,
    health: health,
    maxHealth: maxHealth,
    gold: gold,
    uniqueGames: uniqueBeaten.size,
    totalDistance: gameState.visitedGames.length,
    items: inventory.length,
    startGame: gameState.startGame.name,
    amuletGame: gameState.amuletGame.name,
    escapeLostRuns: gameState.escapeLostRuns,
    strength: strength,
    dexterity: dexterity,
    intelligence: intelligence,
    charisma: charisma,
    luck: luck
  });

  // Delete the current save since run is complete
  if (gameState.saveName && gameSaves[gameState.saveName]) {
    delete gameSaves[gameState.saveName];
    localStorage.setItem('gameSaves', JSON.stringify(gameSaves));
  }

  createGameModal(`
    <div style="text-align: center;">
      <h1 style="color: gold; font-size: 48px; margin: 20px 0;">🏆 VICTORY! 🏆</h1>
      <h2 style="color: #4CAF50;">You Escaped with the Amulet of Nivlac!</h2>

      <div style="background: rgba(0,0,0,0.3); padding: 20px; border-radius: 12px; margin: 30px 0;">
        <h3 style="margin-top: 0; color: #888;">Final Stats</h3>
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 15px; text-align: left; max-width: 400px; margin: 0 auto;">
          <div><strong>Health:</strong></div><div>${health} / ${maxHealth}</div>
          <div><strong>Gold:</strong></div><div style="color: gold;">${gold}</div>
          <div><strong>Unique Games Beaten:</strong></div><div>${uniqueBeaten.size}</div>
          <div><strong>Total Distance:</strong></div><div>${gameState.visitedGames.length}</div>
          <div><strong>Items Collected:</strong></div><div>${inventory.length}</div>
          <div><strong>Character:</strong></div><div>${PLAYER_CHARACTERS[gameState.character].name}</div>
        </div>
      </div>

      <div style="background: rgba(255,215,0,0.1); padding: 15px; border-radius: 8px; border: 2px solid gold; margin: 20px 0;">
        <h4 style="margin: 0; color: gold;">Unlocks</h4>
        <p style="color: #aaa; font-size: 14px; margin: 10px 0;">No unlocks available yet - feature coming soon!</p>
      </div>

      <button onclick="location.reload();" style="margin-top: 20px; padding: 15px 40px; background: linear-gradient(145deg, #4CAF50, #2E7D32); border: none; border-radius: 8px; color: white; cursor: pointer; font-weight: bold; font-size: 16px;">Return to Main Menu</button>
    </div>
  `);
}

function saveRunToHistory(runData) {
  const history = JSON.parse(localStorage.getItem('runHistory') || '[]');
  history.unshift(runData); // Add to beginning

  // Keep only last 50 runs
  if (history.length > 50) {
    history.length = 50;
  }

  localStorage.setItem('runHistory', JSON.stringify(history));
}

function showRunHistory() {
  const history = JSON.parse(localStorage.getItem('runHistory') || '[]');

  if (history.length === 0) {
    createGameModal(`
      <div style="text-align: center; padding: 20px;">
        <h2 style="color: #888;">No Completed Runs</h2>
        <p style="color: #aaa;">Complete a run to see your history here!</p>
        <button onclick="closeGameModal();" style="margin-top: 20px; padding: 10px 30px; background: #666; border: none; border-radius: 6px; color: white; cursor: pointer;">Close</button>
      </div>
    `);
    return;
  }

  let historyHTML = `
    <div style="max-height: 70vh; overflow-y: auto;">
      <h2 style="color: gold; margin-top: 0; text-align: center;">🏆 Victory History</h2>
      <p style="text-align: center; color: #aaa; margin-bottom: 20px;">Your ${history.length} most recent victorious runs</p>
  `;

  history.forEach((run, index) => {
    const date = new Date(run.date);
    const dateStr = date.toLocaleDateString() + ' ' + date.toLocaleTimeString();
    const lostRuns = run.escapeLostRuns ? run.escapeLostRuns.reduce((a, b) => a + b, 0) : 0;

    historyHTML += `
      <div style="background: rgba(0,0,0,0.3); padding: 15px; border-radius: 8px; margin-bottom: 15px; border-left: 4px solid gold;">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
          <strong style="color: gold; font-size: 16px;">Run #${index + 1}</strong>
          <span style="color: #888; font-size: 12px;">${dateStr}</span>
        </div>
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px; font-size: 14px;">
          <div><strong>Character:</strong></div><div>${run.character}</div>
          <div><strong>Health:</strong></div><div style="color: #ff4444;">${run.health} / ${run.maxHealth}</div>
          <div><strong>Gold:</strong></div><div style="color: gold;">${run.gold}</div>
          <div><strong>Unique Games:</strong></div><div>${run.uniqueGames}</div>
          <div><strong>Total Distance:</strong></div><div>${run.totalDistance}</div>
          <div><strong>Items:</strong></div><div>${run.items}</div>
          <div><strong>Strength:</strong></div><div>${run.strength}</div>
          <div><strong>Dexterity:</strong></div><div>${run.dexterity}</div>
          <div><strong>Intelligence:</strong></div><div>${run.intelligence}</div>
          <div><strong>Charisma:</strong></div><div>${run.charisma}</div>
          <div><strong>Luck:</strong></div><div>${run.luck}</div>
          <div><strong>Lost Runs (Escape):</strong></div><div style="color: #ff4444;">${lostRuns}</div>
        </div>
        <div style="margin-top: 10px; padding-top: 10px; border-top: 1px solid #444; font-size: 12px; color: #aaa;">
          <div><strong>Route:</strong> ${run.startGame} → ${run.amuletGame}</div>
        </div>
      </div>
    `;
  });

  historyHTML += `
    </div>
    <div style="text-align: center; margin-top: 20px; padding-top: 15px; border-top: 2px solid #444;">
      <button onclick="closeGameModal();" style="padding: 10px 30px; background: linear-gradient(145deg, #9b59b6, #7d3c98); border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold;">Close</button>
    </div>
  `;

  createGameModal(historyHTML);
}

function markGameFinished(gameName) {
  if (!gameState.finishedGames) {
    gameState.finishedGames = [];
  }

  // Only add if not already in finishedGames array
  if (!gameState.finishedGames.includes(gameName)) {
    gameState.finishedGames.push(gameName);
    console.log(`Game finished: ${gameName}. Total unique finished: ${gameState.finishedGames.length}`);

    // Check and update curse durations
    checkCurseDurations('game_beaten');

    updateGameStats();
    saveCurrentGame();
  }
}

// Add a curse to active curses, processing Curse of Vulnerability if present
function addCurse(curseToAdd) {
  if (!gameState.activeCurses) {
    gameState.activeCurses = [];
  }

  // Add the base curse
  gameState.activeCurses.push({
    name: curseToAdd.name,
    stat: curseToAdd.stat,
    power: curseToAdd.power,
    duration: curseToAdd.duration,
    description: curseToAdd.description
  });

  // Check for Curse of Vulnerability (add duplicate curses)
  const vulnerabilityCurses = gameState.activeCurses.filter(c => c.name.toLowerCase().includes('vulnerability'));
  if (vulnerabilityCurses.length > 0) {
    // Track uses for each vulnerability curse
    if (!gameState.vulnerabilityUses) {
      gameState.vulnerabilityUses = {};
    }

    // Process first available vulnerability curse that has uses left
    for (const vulnerabilityCurse of vulnerabilityCurses) {
      if (!gameState.vulnerabilityUses[vulnerabilityCurse.name]) {
        gameState.vulnerabilityUses[vulnerabilityCurse.name] = 0;
      }

      // Determine max uses based on power
      let maxUses = 1;
      if (vulnerabilityCurse.power === 'Medium') maxUses = 2;
      else if (vulnerabilityCurse.power === 'High') maxUses = 3;

      // If this vulnerability curse still has uses, add a duplicate of the incoming curse
      if (gameState.vulnerabilityUses[vulnerabilityCurse.name] < maxUses) {
        gameState.activeCurses.push({
          name: curseToAdd.name,
          stat: curseToAdd.stat,
          power: curseToAdd.power,
          duration: curseToAdd.duration,
          description: curseToAdd.description
        });

        gameState.vulnerabilityUses[vulnerabilityCurse.name]++;

        // Remove curse if we've used all charges
        if (gameState.vulnerabilityUses[vulnerabilityCurse.name] >= maxUses) {
          const indexToRemove = gameState.activeCurses.indexOf(vulnerabilityCurse);
          if (indexToRemove !== -1) {
            gameState.activeCurses.splice(indexToRemove, 1);
          }
          delete gameState.vulnerabilityUses[vulnerabilityCurse.name];
        }

        // Only use one vulnerability curse per incoming curse
        break;
      }
    }
  }

  // Update curses display
  if (typeof updateCursesDisplay === 'function') {
    updateCursesDisplay();
  }
  if (typeof updateActiveCursesList === 'function') {
    updateActiveCursesList();
  }

  return true;
}

// Check and remove curses based on their duration conditions
function checkCurseDurations(trigger) {
  if (!gameState.activeCurses || gameState.activeCurses.length === 0) return;
  if (!gameState.cursesTracker) {
    gameState.cursesTracker = {};
  }

  const cursesToRemove = [];

  gameState.activeCurses.forEach((curse, index) => {
    // Initialize tracker for this curse if it doesn't exist
    if (!gameState.cursesTracker[curse.name]) {
      gameState.cursesTracker[curse.name] = {
        gamesBeaten: 0,
        spacesChosen: 0,
        combatsLost: 0,
        diceRolled: 0
      };
    }

    const tracker = gameState.cursesTracker[curse.name];

    // Update trackers based on trigger
    if (trigger === 'game_beaten') {
      tracker.gamesBeaten++;
    } else if (trigger === 'space_chosen') {
      tracker.spacesChosen++;
    } else if (trigger === 'combat_lost') {
      tracker.combatsLost++;
    } else if (trigger === 'dice_rolled') {
      tracker.diceRolled++;
    }

    // Check if curse should be removed
    let shouldRemove = false;
    const duration = curse.duration.toLowerCase();

    // Parse duration and check conditions
    if (duration.includes('until') && duration.includes('game')) {
      const match = duration.match(/(\d+)\s+game/);
      if (match) {
        const required = parseInt(match[1]);
        if (tracker.gamesBeaten >= required) {
          shouldRemove = true;
        }
      }
    }

    if (shouldRemove) {
      cursesToRemove.push(index);
      console.log(`Curse removed: ${curse.name}`);
    }
  });

  // Remove expired curses (iterate backwards to avoid index issues)
  for (let i = cursesToRemove.length - 1; i >= 0; i--) {
    const curseToRemove = gameState.activeCurses[cursesToRemove[i]];
    delete gameState.cursesTracker[curseToRemove.name];
    gameState.activeCurses.splice(cursesToRemove[i], 1);
  }

  // Update display if any curses were removed
  if (cursesToRemove.length > 0 && typeof updateCursesDisplay === 'function') {
    updateCursesDisplay();
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
window.loadState = loadState;
window.saveCurrentGame = saveCurrentGame;
window.loadSavedGame = loadSavedGame;
window.createGameModal = createGameModal;
window.closeGameModal = closeGameModal;
window.showCombatModal = showCombatModal;
window.showEventModal = showEventModal;
window.showShopModal = showShopModal;
window.handleEventChoice = handleEventChoice;
window.showItemChoiceModal = showItemChoiceModal;
window.markGameFinished = markGameFinished;
window.checkCurseDurations = checkCurseDurations;
window.addGameStatus = addGameStatus;
window.removeGameStatus = removeGameStatus;
window.hasGameStatus = hasGameStatus;
window.getGameStatuses = getGameStatuses;
window.updateActiveCursesList = updateActiveCursesList;
window.addCurse = addCurse;
window.getGamesWithStatus = getGamesWithStatus;
