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

document.getElementById('increase-gold')?.addEventListener('click', () => {
  gold += 5;
  gameState.gold = gold;
  updateTopBar();
  updateGameStats();
  saveCurrentGame();
});

document.getElementById('decrease-gold')?.addEventListener('click', () => {
  if (gold >= 5) {
    gold -= 5;
  } else {
    gold = 0;
  }
  gameState.gold = gold;
  updateTopBar();
  updateGameStats();
  saveCurrentGame();
});

document.getElementById('increase-health')?.addEventListener('click', () => {
  if (health < maxHealth) {
    health++;
    gameState.health = health;
    updateHealthDisplay();
    updateGameStats();
    saveCurrentGame();
  }
});

document.getElementById('decrease-health')?.addEventListener('click', () => {
  if (health > 0) {
    health--;
    gameState.health = health;
    updateHealthDisplay();
    updateGameStats();
    saveCurrentGame();
  }
});

document.getElementById('increase-max-health')?.addEventListener('click', () => {
  maxHealth++;
  if (health > maxHealth) {
    health = maxHealth;
  }
  gameState.health = health;
  gameState.maxHealth = maxHealth;
  updateHealthDisplay();
  updateGameStats();
  saveCurrentGame();
});

document.getElementById('decrease-max-health')?.addEventListener('click', () => {
  if (maxHealth > 1) {
    maxHealth--;
    if (health > maxHealth) {
      health = maxHealth;
    }
    gameState.health = health;
    gameState.maxHealth = maxHealth;
    updateHealthDisplay();
    updateGameStats();
    saveCurrentGame();
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

  // Spawn initial choices
  if (typeof spawnChoices === 'function') {
    spawnChoices();
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
    background: rgba(0,0,0,0.9);
    display: flex;
    justify-content: center;
    align-items: center;
    z-index: 10000;
    animation: fadeIn 0.3s;
  `;

  const modalContent = document.createElement('div');
  modalContent.className = 'modal-content';
  modalContent.style.cssText = `
    background: #1e1e1e;
    padding: 30px;
    border-radius: 12px;
    max-width: 800px;
    max-height: 90vh;
    overflow-y: auto;
    color: white;
    box-shadow: 0 10px 40px rgba(0,0,0,0.5);
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

  const stats = ['Strength', 'Charisma', 'Intelligence', 'Dexterity'];
  const randomStat = stats[Math.floor(Math.random() * stats.length)];

  let powerText = 'Low';
  if (gameState.beatenGames.length >= 9) {
    powerText = 'High';
  } else if (gameState.beatenGames.length >= 4) {
    powerText = 'Medium';
  }

  const matchingEnemies = enemies.filter(enemy =>
    enemy.powerLevel === powerText && enemy.stat === randomStat
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
      <button id="roll-combat-btn" style="padding: 15px 30px; font-size: 18px; background: #4CAF50; border: none; border-radius: 8px; color: white; cursor: pointer; margin: 10px;">
        Roll D20
      </button>
      <div id="combat-result" style="margin-top: 20px; font-size: 16px;"></div>
    </div>
  `);

  document.getElementById('roll-combat-btn').onclick = () => {
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

      const matchingCurses = curses.filter(curse =>
        curse.powerLevel === powerText && curse.stat === randomStat
      );
      let failureText = enemy.failureConsequence;
      if (matchingCurses.length > 0) {
        const randomCurseIndex = Math.floor(Math.random() * matchingCurses.length);
        const selectedCurse = matchingCurses[randomCurseIndex];
        failureText = `Lose ${healthMatch ? healthMatch[1] : 2} health and gain ${selectedCurse.name} (${selectedCurse.duration})`;
      }

      resultHTML += `<p style="color: #ff4444; font-weight: bold;">FAILURE!</p>
                    <p>${failureText}</p>`;
    }

    resultHTML += `<button onclick="closeGameModal()" style="padding: 10px 20px; margin-top: 20px; background: #666; border: none; border-radius: 6px; color: white; cursor: pointer;">Continue</button>`;

    document.getElementById('combat-result').innerHTML = resultHTML;
    document.getElementById('roll-combat-btn').disabled = true;

    encounterHistory.push({
      type: 'combat',
      enemy: enemy.name,
      outcome: success ? 'Victory' : 'Defeat',
      timestamp: new Date().toLocaleString()
    });
    updateEncounterHistory();
    saveCurrentGame();
  };
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
      e.target.style.background = '#3d3d3d';
    };
    btn.onmouseleave = (e) => {
      e.target.style.transform = '';
      e.target.style.background = '#2d2d2d';
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
        e.target.style.background = '#666';

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
  for (let i = 0; i < 2; i++) {
    const rarityRoll = Math.random() * 100;
    let targetRarity = rarityRoll <= 50 ? 'common' : rarityRoll <= 85 ? 'uncommon' : 'rare';

    const rarityItems = items.filter(item => item.rarity === targetRarity);
    if (rarityItems.length > 0) {
      const randomIndex = Math.floor(Math.random() * rarityItems.length);
      choices.push(rarityItems[randomIndex]);
    } else {
      const randomIndex = Math.floor(Math.random() * items.length);
      choices.push(items[randomIndex]);
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
        <div style="font-size: 20px; font-weight: bold; margin-bottom: 10px;">${item.name}</div>
        <div style="color: ${rarityColor}; font-size: 14px; margin-bottom: 15px;">${item.rarity}</div>
        <div style="color: #ccc; font-size: 14px; line-height: 1.5;">${item.description}</div>
        <div style="color: #888; font-size: 12px; margin-top: 10px; font-style: italic;">${item.type}</div>
      </div>
    `;
  });

  itemsHTML += '</div>';
  itemsHTML += '<p style="text-align: center; color: #888; margin-top: 20px; font-size: 14px;">Click an item to choose it</p>';

  createGameModal(`
    <div>
      <h2 style="color: #f39c12; margin-top: 0; text-align: center;">🎁 Choose Your Reward!</h2>
      <p style="text-align: center; color: #aaa;">Select one item to add to your inventory</p>
      ${itemsHTML}
    </div>
  `);

  document.querySelectorAll('.item-choice-card').forEach(card => {
    card.onmouseenter = (e) => {
      e.currentTarget.style.transform = 'translateY(-5px) scale(1.05)';
      e.currentTarget.style.boxShadow = '0 10px 30px rgba(0,0,0,0.5)';
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
