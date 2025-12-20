// ===== UI.JS - All DOM Manipulation and Display Updates =====
//
// This module handles all visual updates to the UI including:
// - Top bar (health, gold, rations)
// - Inventory display
// - Game lists and selections
// - Encounter history
// - Game state stats sidebar

// ===== TOP BAR UPDATES =====

function updateTopBar() {
  document.getElementById('rations-total').textContent = rations;
  document.getElementById('gold-total').textContent = gold;
  updateHealthDisplay();
}

function updateHealthDisplay() {
  document.getElementById('health-display').textContent = `${health}/${maxHealth}`;
  const healthPercentage = (health / maxHealth) * 100;
  document.getElementById('health-bar').style.width = `calc(${healthPercentage}% + 1px)`;
}

// ===== INVENTORY DISPLAY =====

function updateInventory() {
  const inventoryDiv = document.getElementById('inventory');
  inventoryDiv.innerHTML = '';

  const removeItemSelect = document.getElementById('removeItemSelect');
  removeItemSelect.innerHTML = '<option value="">-- Select an Item --</option>';

  inventory.forEach((item, index) => {
    const itemDiv = document.createElement('div');
    itemDiv.className = 'inventory-item';
    itemDiv.innerHTML = `
      <strong>${item.name}</strong> (${item.rarity})
      <span class="remove-item" onclick="removeItem(${index})">×</span>
      <p>${item.description}</p>
      <p><em>Type: ${item.type}</em></p>
    `;
    inventoryDiv.appendChild(itemDiv);

    const option = document.createElement('option');
    option.value = index;
    option.textContent = `${item.name} (${item.rarity})`;
    removeItemSelect.appendChild(option);
  });

  removeItemSelect.disabled = inventory.length === 0;
  document.getElementById('removeSelectedItem').disabled = inventory.length === 0;
  document.getElementById('removeRandomItem').disabled = inventory.length === 0;

  // Update game items sidebar if it exists
  const gameItemsList = document.getElementById('game-items-list');
  if (gameItemsList) {
    if (inventory.length === 0) {
      gameItemsList.innerHTML = '<div class="empty-inventory">No items yet</div>';
    } else {
      gameItemsList.innerHTML = inventory.map(item => `
        <div class="item-display ${item.rarity}">
          <div class="item-name">${item.name}</div>
          <div class="item-rarity">${item.rarity}</div>
          <div class="item-description">${item.description}</div>
        </div>
      `).join('');
    }
  }
}

// ===== GAME LISTS =====

function updateExcludedGamesList() {
  const excludedGamesListDiv = document.getElementById('excludedGamesList');
  excludedGamesListDiv.innerHTML = '';
  excludedGames.forEach((game, index) => {
    const gameDiv = document.createElement('div');
    gameDiv.className = 'excluded-game';
    gameDiv.innerHTML = `
      <strong>${game}</strong>
      <span class="remove-excluded-game" onclick="removeExcludedGame(${index})">×</span>
    `;
    excludedGamesListDiv.appendChild(gameDiv);
  });
}

function updateBeatenGamesList() {
  const beatenGamesListDiv = document.getElementById('beatenGamesList');
  beatenGamesListDiv.innerHTML = '';
  beatenGames.forEach((game, index) => {
    const gameDiv = document.createElement('div');
    gameDiv.className = 'beaten-game';
    gameDiv.innerHTML = `
      <strong>${game}</strong>
      <span class="remove-game" onclick="removeBeatenGame(${index})">×</span>
    `;
    beatenGamesListDiv.appendChild(gameDiv);
  });

  populateEscapeGameDropdown();
  document.getElementById('randomSelectForPhase2').disabled = beatenGames.length < 3;
}

function populateEscapeGameDropdown() {
  const selectGameForEscape = document.getElementById('selectGameForEscape');
  selectGameForEscape.innerHTML = '<option value="">-- Select a Game --</option>';
  beatenGames.forEach(game => {
    const option = document.createElement('option');
    option.value = game;
    option.textContent = game;
    selectGameForEscape.appendChild(option);
  });

  selectGameForEscape.disabled = beatenGames.length < 3;
  document.getElementById('addGameForEscape').disabled = beatenGames.length < 3;
}

function updateSelectedGamesDisplay() {
  const selectedGamesDiv = document.getElementById('selectedGames');
  selectedGamesDiv.innerHTML = '';
  selectedPhase2Games.forEach((game, index) => {
    const gameDiv = document.createElement('div');
    gameDiv.className = 'beaten-game';
    gameDiv.innerHTML = `
      <strong>${game}</strong>
      <span class="remove-selected-game" onclick="removeSelectedGame(${index})">×</span>
    `;
    selectedGamesDiv.appendChild(gameDiv);
  });

  if (selectedPhase2Games.length >= 3) {
    document.getElementById('selectGameForEscape').disabled = true;
    document.getElementById('addGameForEscape').disabled = true;
    document.getElementById('randomSelectForPhase2').disabled = true;
  }
}

// ===== PACT OF PUNISHMENT =====

function updateRoguePointsDisplay() {
  document.getElementById('rogue-points-display').textContent = `Rogue Points: ${roguePoints}`;
}

function updateConditionCounts() {
  document.getElementById('lessHealth-count').textContent = pactConditions.lessHealth;
  document.getElementById('moreGames-count').textContent = pactConditions.moreGames;
  document.getElementById('randomGame-count').textContent = pactConditions.randomGame;
  document.getElementById('challengeRun-count').textContent = pactConditions.challengeRun;
}

// ===== ENCOUNTER HISTORY =====

function updateEncounterHistory() {
  const historyDiv = document.getElementById('encounterHistory');
  historyDiv.innerHTML = '';

  encounterHistory.forEach((encounter, index) => {
    const encounterDiv = document.createElement('div');
    encounterDiv.className = 'encounter-history-item';

    if (encounter.type === 'event') {
      encounterDiv.innerHTML = `
        <strong>${encounter.name}</strong>
        <span class="remove-history-item" onclick="removeEncounterHistoryItem(${index})">×</span>
        <p>${encounter.option}</p>
        <small>${encounter.timestamp}</small>
      `;
    } else if (encounter.type === 'combat') {
      encounterDiv.innerHTML = `
        <strong>Combat: ${encounter.enemy}</strong>
        <span class="remove-history-item" onclick="removeEncounterHistoryItem(${index})">×</span>
        <p>${encounter.outcome}</p>
        <small>${encounter.timestamp}</small>
      `;
    }

    historyDiv.appendChild(encounterDiv);
  });
}

// ===== GAME STATS SIDEBAR =====

function updateGameStats() {
  // Update stats in the game view sidebar
  const statsHealth = document.getElementById('stats-health');
  const statsGold = document.getElementById('stats-gold');
  const statsStrength = document.getElementById('stats-strength');
  const statsDexterity = document.getElementById('stats-dexterity');
  const statsIntelligence = document.getElementById('stats-intelligence');
  const statsCharisma = document.getElementById('stats-charisma');
  const statsLuck = document.getElementById('stats-luck');
  const statsItems = document.getElementById('stats-items');
  const statsGames = document.getElementById('stats-games');
  const statsDistance = document.getElementById('stats-distance');

  if (statsHealth) statsHealth.textContent = `${health}/${maxHealth}`;
  if (statsGold) statsGold.textContent = gold;
  if (statsStrength) statsStrength.textContent = strength;
  if (statsDexterity) statsDexterity.textContent = dexterity;
  if (statsIntelligence) statsIntelligence.textContent = intelligence;
  if (statsCharisma) statsCharisma.textContent = charisma;
  if (statsLuck) statsLuck.textContent = luck;
  if (statsItems) statsItems.textContent = inventory.length;

  // Games = unique games beaten
  if (statsGames) {
    const uniqueBeaten = new Set(gameState.beatenGames || beatenGames);
    statsGames.textContent = uniqueBeaten.size;
  }

  // Distance = total games played (including replays)
  if (statsDistance) {
    statsDistance.textContent = gameState.visitedGames?.length || 0;
  }
}

// ===== SAVE/LOAD LIST =====

function updateSaveList() {
  const saveList = document.getElementById('save-list');
  if (!saveList) return;

  saveList.innerHTML = '';

  for (const [saveName, save] of Object.entries(gameSaves)) {
    const saveItem = document.createElement('div');
    saveItem.style.cssText = 'padding: 10px 15px; cursor: pointer; border-bottom: 1px solid #444;';

    const characterName = PLAYER_CHARACTERS[save.character]?.name || 'Unknown';
    saveItem.innerHTML = `
      <div style="font-weight: bold; color: white;">${saveName}</div>
      <div style="font-size: 11px; color: #888;">
        ${characterName} | Health: ${save.health}/${save.maxHealth} | Gold: ${save.gold} | Games: ${save.beatenGames?.length || 0}
      </div>
    `;

    saveItem.onclick = () => {
      loadSavedGame(saveName);
      saveList.style.display = 'none';
    };

    saveItem.onmouseenter = (e) => { e.target.style.background = '#3d3d3d'; };
    saveItem.onmouseleave = (e) => { e.target.style.background = ''; };

    saveList.appendChild(saveItem);
  }

  const deleteBtn = document.createElement('div');
  deleteBtn.style.cssText = 'padding: 10px 15px; cursor: pointer; color: #ff4444; text-align: center;';
  deleteBtn.textContent = 'Delete All Saves';
  deleteBtn.onclick = () => {
    if (confirm('Delete all saved games?')) {
      gameSaves = {};
      localStorage.setItem('roguelikeGameSaves', JSON.stringify(gameSaves));
      updateSaveList();
    }
  };
  saveList.appendChild(deleteBtn);
}

// Export functions to global scope for backwards compatibility
window.updateTopBar = updateTopBar;
window.updateHealthDisplay = updateHealthDisplay;
window.updateInventory = updateInventory;
window.updateExcludedGamesList = updateExcludedGamesList;
window.updateBeatenGamesList = updateBeatenGamesList;
window.updateSelectedGamesDisplay = updateSelectedGamesDisplay;
window.updateRoguePointsDisplay = updateRoguePointsDisplay;
window.updateConditionCounts = updateConditionCounts;
window.updateEncounterHistory = updateEncounterHistory;
window.updateGameStats = updateGameStats;
window.updateSaveList = updateSaveList;
window.populateEscapeGameDropdown = populateEscapeGameDropdown;
