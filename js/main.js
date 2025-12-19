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
    charisma: charisma
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

  // Show dungeon screen
  document.getElementById('main-menu').style.display = 'none';
  document.getElementById('dungeon-screen').style.display = 'block';

  // Render the game state
  if (typeof renderGameState === 'function') {
    renderGameState();
  }

  updateTopBar();
  updateInventory();
  updateGameStats();

  console.log('Game loaded:', saveName);
}

// ===== TUTORIAL AND UI CONTROLS =====

document.getElementById('toggleTutorial')?.addEventListener('click', () => {
  const tutorial = document.getElementById('tutorial');
  if (tutorial.style.display === 'none') {
    tutorial.style.display = 'block';
  } else {
    tutorial.style.display = 'none';
  }
});

document.getElementById('clearAllData')?.addEventListener('click', () => {
  if (confirm('This will delete ALL saved games and reset the app. Are you sure?')) {
    localStorage.clear();
    location.reload();
  }
});

// ===== TOP BAR EVENT LISTENERS =====

document.getElementById('increase-rations')?.addEventListener('click', () => {
  rations++;
  updateTopBar();
});

document.getElementById('decrease-rations')?.addEventListener('click', () => {
  if (rations > 0) rations--;
  updateTopBar();
});

document.getElementById('increase-gold')?.addEventListener('click', () => {
  gold += 5;
  updateTopBar();
});

document.getElementById('decrease-gold')?.addEventListener('click', () => {
  if (gold >= 5) {
    gold -= 5;
  } else {
    gold = 0;
  }
  updateTopBar();
});

document.getElementById('increase-health')?.addEventListener('click', () => {
  if (health < maxHealth) {
    health++;
    updateHealthDisplay();
  }
});

document.getElementById('decrease-health')?.addEventListener('click', () => {
  if (health > 0) {
    health--;
    updateHealthDisplay();
  }
});

document.getElementById('increase-max-health')?.addEventListener('click', () => {
  maxHealth++;
  if (health > maxHealth) {
    health = maxHealth;
  }
  updateHealthDisplay();
});

document.getElementById('decrease-max-health')?.addEventListener('click', () => {
  if (maxHealth > 1) {
    maxHealth--;
    if (health > maxHealth) {
      health = maxHealth;
    }
    updateHealthDisplay();
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
        opt.style.border = '3px solid #555';
      });
      charDiv.style.border = '3px solid gold';
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

  gameState = {
    currentGame: start.name,
    visitedGames: [start.name],
    saveName: saveName,
    gameStarted: true,
    health: health,
    maxHealth: maxHealth,
    gold: gold,
    inventory: [...inventory],
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
  document.getElementById('dungeon-screen').style.display = 'block';

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

document.getElementById('return-menu')?.addEventListener('click', () => {
  if (confirm('Return to main menu? (Game will be saved)')) {
    saveCurrentGame();
    document.getElementById('dungeon-screen').style.display = 'none';
    document.getElementById('main-menu').style.display = 'flex';
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
        description: String(row[4])
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

// Export to global scope
window.loadState = loadState;
window.saveCurrentGame = saveCurrentGame;
window.loadSavedGame = loadSavedGame;
