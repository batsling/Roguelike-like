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

  // Show dungeon screen
  document.getElementById('main-menu').style.display = 'none';
  document.getElementById('dungeon-screen').style.display = 'flex';

  // Render the game state
  if (typeof renderGameState === 'function') {
    renderGameState();
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
  console.log('Start Run button clicked. games.length:', games.length);
  if (games.length === 0) {
    alert('Please upload an Excel file first!');
    return;
  }

  // Populate character selection
  const charSelection = document.getElementById('character-selection');
  charSelection.innerHTML = '';

  for (const [id, char] of Object.entries(PLAYER_CHARACTERS)) {
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
  const character = PLAYER_CHARACTERS[selectedCharacter];
  strength = character.startingStats.strength;
  dexterity = character.startingStats.dexterity;
  intelligence = character.startingStats.intelligence;
  charisma = character.startingStats.charisma;
  reroll = character.startingStats.reroll || 0;
  dash = character.startingStats.dash || 0;
  skip = character.startingStats.skip || 0;
  discovery = character.startingStats.discovery || 0;

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
    escapeProgress: 0
  };

  startGame = start;
  amuletGame = amulet;

  // Hide modal and menu
  document.getElementById('save-modal').style.display = 'none';
  document.getElementById('main-menu').style.display = 'none';
  document.getElementById('dungeon-screen').style.display = 'flex';

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

// ===== EXCEL FILE UPLOAD =====

document.getElementById('excelFile')?.addEventListener('change', function(event) {
  const file = event.target.files[0];
  if (file) {
    const reader = new FileReader();
    reader.onload = function(e) {
      const data = new Uint8Array(e.target.result);
      const workbook = XLSX.read(data, { type: 'array' });

      const gamesSheet = workbook.Sheets[workbook.SheetNames[0]];
      const gamesData = XLSX.utils.sheet_to_json(gamesSheet, { header: 1 });
      games = gamesData.slice(1).map(row => ({
        name: String(row[0]),
        year: parseInt(row[1]),
        type: String(row[2]),
        connected: String(row[3]).toUpperCase() === "TRUE",
        influenced: String(row[4]).toUpperCase() === "TRUE"
      }));

      const connectionsSheet = workbook.Sheets[workbook.SheetNames[1]];
      const connectionsData = XLSX.utils.sheet_to_json(connectionsSheet, { header: 1 });
      connections = connectionsData.slice(1).map(row => ({
        influencer: String(row[0]),
        influencee: String(row[1])
      }));

      const itemsSheet = workbook.Sheets[workbook.SheetNames[2]];
      const itemsData = XLSX.utils.sheet_to_json(itemsSheet, { header: 1 });
      items = itemsData.slice(1).map(row => ({
        name: String(row[0]),
        rarity: String(row[1]).toLowerCase(),
        type: String(row[3]).trim(),
        description: String(row[4]),
        image: row[5] ? String(row[5]).trim() : '', // Column 6: Image URL
        game: row[6] ? String(row[6]).trim() : ''   // Column 7: Game name
      }));

      if (workbook.SheetNames.length > 3) {
        const eventsSheet = workbook.Sheets[workbook.SheetNames[3]];
        const eventsData = XLSX.utils.sheet_to_json(eventsSheet, { header: 1 });
        events = eventsData.slice(1).map(row => ({
          name: String(row[0]),
          description: String(row[1]),
          options: [
            String(row[2] || ""),
            String(row[3] || ""),
            String(row[4] || ""),
            String(row[5] || "")
          ].filter(opt => opt.trim() !== "")
        }));
      }

      if (workbook.SheetNames.length > 4) {
        const enemiesSheet = workbook.Sheets[workbook.SheetNames[4]];
        const enemiesData = XLSX.utils.sheet_to_json(enemiesSheet, { header: 1 });
        enemies = enemiesData.slice(1).map(row => ({
          name: String(row[0]),
          powerLevel: String(row[1]),
          game: String(row[2]),
          stat: String(row[3]),
          rollCheck: parseInt(row[4]),
          successReward: String(row[5]),
          failureConsequence: String(row[6]),
          imageUrl: String(row[7])
        }));
      }

      if (workbook.SheetNames.length > 5) {
        const cursesSheet = workbook.Sheets[workbook.SheetNames[5]];
        const cursesData = XLSX.utils.sheet_to_json(cursesSheet, { header: 1 });
        curses = cursesData.slice(1).map(row => ({
          name: String(row[0]),
          stat: String(row[1]),
          powerLevel: String(row[2]),
          duration: String(row[3]),
          description: String(row[4])
        }));
      }

      // Populate UI elements
      populateGameSelects();
      populateItemSelects();
      enableButtons();

      console.log('Excel data loaded successfully. Games:', games.length, 'Items:', items.length);

      try {
        updateSaveList();
      } catch(err) {
        console.error('Error in updateSaveList:', err);
      }
    };
    reader.readAsArrayBuffer(file);
  }
});

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
    const totalRoll = diceRoll + playerStatValue;
    const success = totalRoll >= enemy.rollCheck;

    let resultHTML = `
      <div style="background: rgba(0,0,0,0.3); padding: 15px; border-radius: 8px; margin: 10px 0;">
        <p style="font-size: 20px; font-weight: bold;">Dice: ${diceRoll}</p>
        <p style="font-size: 16px; color: ${getStatColor(enemy.stat)};">+ ${enemy.stat} Bonus: ${playerStatValue}</p>
        <p style="font-size: 24px; font-weight: bold; margin-top: 10px; color: gold;">Total: ${totalRoll}</p>
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
      resultHTML += `<p style="color: #4CAF50; font-weight: bold;">SUCCESS!</p>
                    <p>${enemy.successReward}</p>`;
    } else {
      const healthMatch = enemy.failureConsequence.match(/(\d+) health/);
      if (healthMatch) {
        const healthLoss = parseInt(healthMatch[1]);
        health = Math.max(0, health - healthLoss);
        gameState.health = health;
        updateHealthDisplay();
      }

      // Apply curse based on enemy's failure trigger
      const matchingCurses = curses.filter(curse =>
        curse.power === powerText && curse.stat === enemy.stat
      );
      let failureText = enemy.failureConsequence;
      if (matchingCurses.length > 0) {
        const randomCurseIndex = Math.floor(Math.random() * matchingCurses.length);
        const selectedCurse = matchingCurses[randomCurseIndex];

        // Add curse to active curses if not already present
        if (!gameState.activeCurses) {
          gameState.activeCurses = [];
        }

        // Check if curse is already active
        const alreadyHasCurse = gameState.activeCurses.some(c => c.name === selectedCurse.name);
        if (!alreadyHasCurse) {
          gameState.activeCurses.push({
            name: selectedCurse.name,
            stat: selectedCurse.stat,
            power: selectedCurse.power,
            duration: selectedCurse.duration,
            description: selectedCurse.description
          });

          // Update curses display
          if (typeof updateCursesDisplay === 'function') {
            updateCursesDisplay();
          }
        }

        failureText = `Lose ${healthMatch ? healthMatch[1] : 2} health and gain ${selectedCurse.name}!`;
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

function showShopModal() {
  if (items.length === 0) return;

  const shopItems = [];
  for (let i = 0; i < 3; i++) {
    const rarityRoll = Math.random() * 100;
    let targetRarity = rarityRoll <= 50 ? 'common' : rarityRoll <= 85 ? 'uncommon' : 'rare';

    const rarityItems = items.filter(item => item.rarity === targetRarity);
    if (rarityItems.length > 0) {
      const randomIndex = Math.floor(Math.random() * rarityItems.length);
      shopItems.push(rarityItems[randomIndex]);
    }
  }

  let itemsHTML = '<div style="display: flex; flex-direction: column; gap: 15px; margin-top: 20px;">';

  shopItems.forEach((item, index) => {
    const price = item.rarity === 'common' ? 10 : item.rarity === 'uncommon' ? 25 : 50;
    const rarityColor = item.rarity === 'common' ? '#aaa' : item.rarity === 'uncommon' ? '#4CAF50' : '#9b59b6';

    itemsHTML += `
      <div style="padding: 15px; background: #2d2d2d; border-radius: 8px; border: 2px solid ${rarityColor};">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px;">
          <strong style="font-size: 18px;">${item.name}</strong>
          <span style="color: ${rarityColor}; font-size: 14px;">${item.rarity}</span>
        </div>
        <p style="color: #ccc; margin: 10px 0;">${item.description}</p>
        <div style="display: flex; justify-content: space-between; align-items: center; margin-top: 10px;">
          <span style="color: gold; font-weight: bold;">${price} Gold</span>
          <button class="shop-buy-btn" data-index="${index}" data-price="${price}" style="
            padding: 8px 16px;
            background: #4CAF50;
            border: none;
            border-radius: 6px;
            color: white;
            cursor: pointer;
          " ${gold < price ? 'disabled style="opacity: 0.5; cursor: not-allowed;"' : ''}>
            ${gold >= price ? 'Buy' : 'Too Expensive'}
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
        inventory.push(item);
        gameState.inventory = [...inventory];
        updateTopBar();
        updateInventory();

        e.target.textContent = 'Purchased!';
        e.target.disabled = true;
        e.target.style.background = '#555';

        saveCurrentGame();
      }
    };
  });
}

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
      const rarityRoll = Math.random() * 100;
      let targetRarity = rarityRoll <= 50 ? 'common' : rarityRoll <= 85 ? 'uncommon' : 'rare';

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

  let itemsHTML = '<div style="display: flex; gap: 20px; margin-top: 20px; justify-content: center;">';

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

  // Add Reroll button
  const rerollButtonHTML = `
    <div style="text-align: center; margin-top: 20px;">
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
    </div>
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

      inventory.push(item);
      gameState.inventory = [...inventory];
      updateInventory();

      closeGameModal();

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
}

// ===== ESCAPE PHASE =====

function startEscapePhase() {
  gameState.escapePhase = true;
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
      <p style="text-align: center; color: #ff4444; font-size: 14px;">Each game will cost 2 health to complete!</p>
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
    closeGameModal();
    showEscapeVisualization();
  };
}

function showEscapeVisualization() {
  // Hide the main dungeon view and show escape view
  document.getElementById('path-viewport').style.display = 'none';
  document.getElementById('game-hud').style.display = 'none';
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

  const dungeonScreen = document.getElementById('dungeon-screen');
  dungeonScreen.appendChild(escapeContainer);

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
    createGameModal(`
      <div style="text-align: center;">
        <h2 style="color: #ff4444;">You Have Perished!</h2>
        <p>You ran out of health during your escape...</p>
        <p style="color: gold;">You made it ${gameState.escapeProgress} / ${gameState.escapeGames.length} of the way out with the amulet.</p>
        <button onclick="closeGameModal(); location.reload();" style="margin-top: 20px; padding: 12px 30px; background: #666; border: none; border-radius: 6px; color: white; cursor: pointer;">Return to Menu</button>
      </div>
    `);
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
