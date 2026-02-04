/**
 * ESCAPE.JS - Escape Phase, Victory, Run History, and Collection
 *
 * Responsibilities:
 * - Escape phase game selection and visualization
 * - Lost run tracking and death handling
 * - Victory screen and run history
 * - Collection viewing (games, items, enemies, curses)
 * - Sorting and filtering collections
 *
 * Key Functions:
 * - startEscapePhase() - Initiates escape phase with game selection
 * - showEscapeVisualization() - Creates visual escape interface
 * - recordLostRun(index) - Handles lost runs with HP penalty
 * - showVictoryScreen() - Displays victory with final stats
 * - showCollection() - Shows collection modal with tabs
 */

// ===== ESCAPE PHASE =====

function startEscapePhase() {
  gameState.escapePhase = true;
  gameState.phase = 'escape';
  gameState.escapeGames = [];
  gameState.escapeProgress = 0;

  // Get unique visited games (including the amulet game)
  const visitedGames = [...new Set(gameState.visitedGames)];

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
    max-width: 96px;
    max-height: 96px;
    min-width: 64px;
    min-height: 64px;
    object-fit: contain;
    image-rendering: pixelated;
    transition: all 0.5s ease;
    z-index: 100;
  `;
  escapeContainer.appendChild(playerIcon);

  const playerDiv = document.createElement('div');
  playerDiv.id = 'escape-player-position';
  playerDiv.style.cssText = 'text-align: center; position: relative;';
  playerDiv.innerHTML = `
    <div style="width: 72px; height: 72px;"></div>
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
  let damage = 1;

  // Apply damage reduction from items (like Garlic)
  if (typeof calculateDamageReduction === 'function') {
    damage = calculateDamageReduction(damage);
  }

  health = Math.max(0, health - damage);
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

        // Hide map button when in menu
        const mapBtn = document.getElementById('map-btn');
        if (mapBtn) mapBtn.style.display = 'none';
      };

      document.getElementById('escape-death-retry-btn').onclick = () => {
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

        // Hide map button when in menu
        const mapBtn = document.getElementById('map-btn');
        if (mapBtn) mapBtn.style.display = 'none';

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

  // Increment amulet stat for successful escape
  if (gameState.amuletGame) {
    incrementGameBeaten(gameState.amuletGame.name, true);
  }

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
    GameStorage.save(STORAGE_KEYS.SAVED_GAMES, gameSaves);
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
  const history = GameStorage.load(STORAGE_KEYS.RUN_HISTORY, []);
  history.unshift(runData); // Add to beginning

  // Keep only last 50 runs
  if (history.length > 50) {
    history.length = 50;
  }

  GameStorage.save(STORAGE_KEYS.RUN_HISTORY, history);
}

function showRunHistory() {
  const history = GameStorage.load(STORAGE_KEYS.RUN_HISTORY, []);

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

function showCollection() {
  const collectionHTML = `
    <div style="width: 90vw; max-width: 1400px; max-height: 85vh; overflow: hidden; display: flex; flex-direction: column;">
      <!-- Tab Navigation at top -->
      <div style="display: flex; gap: 10px; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 2px solid #444; align-items: center;">
        <h2 style="color: #ff9800; margin: 0; flex: 1;">📚 Collection</h2>
        <button onclick="switchCollectionTab('games')" id="tab-games" style="padding: 8px 16px; background: #ff9800; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 13px;">Games (${games.length})</button>
        <button onclick="switchCollectionTab('items')" id="tab-items" style="padding: 8px 16px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 13px;">Items (${items.length})</button>
        <button onclick="switchCollectionTab('loot')" id="tab-loot" style="padding: 8px 16px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 13px;">Loot</button>
        <button onclick="switchCollectionTab('enemies')" id="tab-enemies" style="padding: 8px 16px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 13px;">Enemies (${enemies.length})</button>
        <button onclick="switchCollectionTab('curses')" id="tab-curses" style="padding: 8px 16px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 13px;">Curses (${curses.length})</button>
        <button onclick="closeGameModal();" style="padding: 8px 20px; background: #444; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 13px;">Close</button>
      </div>

      <!-- Tab Content -->
      <div id="collection-content" style="flex: 1; overflow: hidden; display: flex; gap: 20px;">
        <!-- Content will be populated by switchCollectionTab -->
      </div>
    </div>
  `;

  createGameModal(collectionHTML);
  switchCollectionTab('games');
}

function switchCollectionTab(tab) {
  // Update tab buttons
  const tabs = ['games', 'items', 'loot', 'enemies', 'curses'];
  tabs.forEach(t => {
    const btn = document.getElementById(`tab-${t}`);
    if (btn) {
      btn.style.background = t === tab ? '#ff9800' : '#555';
    }
  });

  const content = document.getElementById('collection-content');
  if (!content) return;

  if (tab === 'games') {
    // Sort games alphabetically
    const sortedGames = [...games].sort((a, b) => a.name.localeCompare(b.name));

    // Get game stats for amulet icons
    const allStats = getGameStats();

    content.innerHTML = `
      <!-- Left side: Game grid -->
      <div id="games-grid" style="flex: 2; overflow-y: auto; padding: 10px;">
        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 15px;">
          ${sortedGames.map(game => {
            const gameStats = allStats[game.name] || { beaten: 0, amulets: 0 };
            return `
            <div
              class="collection-game-card"
              data-game-name="${game.name.replace(/"/g, '&quot;')}"
              onclick="showGameDetails('${game.name.replace(/'/g, "\\'")}')"
              style="
                position: relative;
                background: rgba(0,0,0,0.3);
                border: 1px solid #444;
                border-radius: 8px;
                padding: 10px;
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 8px;
                transition: transform 0.2s, border-color 0.2s;
                cursor: pointer;
              "
              onmouseover="this.style.transform='translateY(-5px)'; this.style.borderColor='#ff9800';"
              onmouseout="this.style.transform=''; this.style.borderColor='#444';">
              ${gameStats.amulets > 0 ? `
                <div style="
                  position: absolute;
                  top: 5px;
                  left: 5px;
                  background: linear-gradient(145deg, gold, #cc9900);
                  border: 2px solid #000;
                  border-radius: 50%;
                  width: 28px;
                  height: 28px;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  font-size: 16px;
                  z-index: 10;
                  box-shadow: 0 2px 6px rgba(0,0,0,0.5);
                ">🏺</div>
              ` : ''}
              <img
                src="${game.coverImage || 'images/covers/no-cover.svg'}"
                alt="${game.name}"
                style="
                  width: 100%;
                  aspect-ratio: 2/3;
                  object-fit: contain;
                  border-radius: 6px;
                  background: #1a1a1a;
                "
              />
              <div style="text-align: center; font-size: 12px; font-weight: bold; color: #ddd; word-wrap: break-word; width: 100%;">
                ${game.name}
              </div>
              <div style="font-size: 10px; color: #888;">
                ${game.year} • ${game.type}
              </div>
            </div>
          `;}).join('')}
        </div>
      </div>

      <!-- Right side: Game details -->
      <div id="game-details" style="flex: 1; overflow-y: auto; padding: 20px; background: rgba(0,0,0,0.2); border: 1px solid #444; border-radius: 8px; min-width: 300px;">
        <div style="text-align: center; color: #888; padding: 40px 20px;">
          <p>Click a game to view details</p>
        </div>
      </div>
    `;
  } else if (tab === 'items') {
    // Initialize filter state if not set
    if (typeof window.itemsShowNA === 'undefined') {
      window.itemsShowNA = false; // Default: hide N/A items
    }

    // Get rarity color function (case-insensitive)
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

    // Filter and sort items
    let filteredItems = window.itemsShowNA ? [...items] : items.filter(item => {
      const rarity = (item.rarity || '').toLowerCase();
      return rarity !== 'n/a';
    });
    let sortedItems = filteredItems.sort((a, b) => a.name.localeCompare(b.name));

    const naCount = items.filter(item => (item.rarity || '').toLowerCase() === 'n/a').length;

    content.innerHTML = `
      <div style="flex: 1; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
        <!-- Sort and Filter controls -->
        <div style="display: flex; gap: 10px; margin-bottom: 15px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center; flex-wrap: wrap;">
          <span style="color: #aaa; font-size: 13px; font-weight: bold;">Sort:</span>
          <button onclick="sortCollectionItems('alphabetical')" id="sort-alpha" style="padding: 6px 12px; background: #ff9800; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">A-Z</button>
          <button onclick="sortCollectionItems('rarity')" id="sort-rarity" style="padding: 6px 12px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Rarity</button>
          <button onclick="sortCollectionItems('game')" id="sort-game" style="padding: 6px 12px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Game</button>
          <div style="border-left: 1px solid #555; height: 20px; margin: 0 5px;"></div>
          <span style="color: #aaa; font-size: 13px; font-weight: bold;">Filter:</span>
          <button onclick="toggleItemsNA()" id="filter-na" style="padding: 6px 12px; background: ${window.itemsShowNA ? '#ff9800' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">
            ${window.itemsShowNA ? 'Hide' : 'Show'} N/A (${naCount})
          </button>
          <span style="color: #666; font-size: 11px; margin-left: auto;">Showing ${sortedItems.length} of ${items.length}</span>
        </div>

        <div id="items-grid" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 15px;">
          ${sortedItems.map(item => {
            const rarityColor = getRarityColor(item.rarity);
            return `
            <div style="
              background: rgba(0,0,0,0.3);
              border: 2px solid ${rarityColor};
              border-radius: 8px;
              padding: 10px;
              display: flex;
              flex-direction: column;
              gap: 8px;
              transition: transform 0.2s, box-shadow 0.2s;
            " onmouseover="this.style.transform='translateY(-5px)'; this.style.boxShadow='0 8px 20px rgba(${rarityColor === '#ff6b00' ? '255,107,0' : rarityColor === '#9b59b6' ? '155,89,182' : rarityColor === '#4CAF50' ? '76,175,80' : '170,170,170'}, 0.4)';" onmouseout="this.style.transform=''; this.style.boxShadow='';">
              <img
                src="${item.image || 'images/items/no-item.svg'}"
                alt="${item.name}"
                style="
                  width: 100%;
                  height: 120px;
                  object-fit: contain;
                  border-radius: 6px;
                  background: rgba(0,0,0,0.2);
                  image-rendering: pixelated;
                "
                onerror="this.style.display='none';"
              />
              <div style="text-align: center; font-size: 12px; font-weight: bold; color: ${rarityColor}; word-wrap: break-word;">
                ${item.name}
              </div>
              <div style="font-size: 10px; color: ${rarityColor}; text-align: center; text-transform: uppercase; font-weight: bold;">
                ${item.rarity}
              </div>
              <div style="font-size: 10px; color: #888; text-align: center; font-style: italic;">
                ${item.game || 'Unknown'}
              </div>
              <div style="font-size: 10px; color: #aaa; text-align: center; line-height: 1.4;">
                ${item.description || 'No description'}
              </div>
            </div>
          `;
          }).join('')}
        </div>
      </div>
    `;
  } else if (tab === 'loot') {
    // Initialize loot sub-tab if not set
    if (!window.currentLootSubTab) {
      window.currentLootSubTab = 'fish';
    }

    content.innerHTML = `
      <div style="flex: 1; display: flex; flex-direction: column; overflow: hidden;">
        <!-- Loot Sub-tabs -->
        <div style="display: flex; gap: 10px; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 1px solid #444;">
          <button onclick="switchLootSubTab('fish')" id="loot-subtab-fish" style="padding: 6px 14px; background: ${window.currentLootSubTab === 'fish' ? '#66b3ff' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">🐟 Fish</button>
        </div>

        <!-- Loot Sub-tab Content -->
        <div id="loot-subtab-content" style="flex: 1; overflow-y: auto;">
          <!-- Content will be populated by switchLootSubTab -->
        </div>
      </div>
    `;

    // Load the current sub-tab content
    switchLootSubTab(window.currentLootSubTab);
  } else if (tab === 'enemies') {
    // Initialize sort state if not set
    if (!window.enemySortType) {
      window.enemySortType = 'name';
    }

    // Filter out variants (they'll be shown in the details panel of their base enemy)
    // and filter out N/A difficulty enemies (variants/transformations)
    const baseEnemies = enemies.filter(e => !e.variantOf && e.difficulty !== 'N/A');

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

    // Sort enemies based on current sort type
    const difficultyOrder = { 'low': 1, 'medium': 2, 'high': 3, 'boss': 4 };
    let sortedEnemies;
    if (window.enemySortType === 'name') {
      sortedEnemies = [...baseEnemies].sort((a, b) => a.name.localeCompare(b.name));
    } else if (window.enemySortType === 'type') {
      sortedEnemies = [...baseEnemies].sort((a, b) => {
        const typeDiff = (a.type || '').localeCompare(b.type || '');
        return typeDiff !== 0 ? typeDiff : a.name.localeCompare(b.name);
      });
    } else if (window.enemySortType === 'game') {
      sortedEnemies = [...baseEnemies].sort((a, b) => {
        const gameDiff = (a.game || '').localeCompare(b.game || '');
        return gameDiff !== 0 ? gameDiff : a.name.localeCompare(b.name);
      });
    } else if (window.enemySortType === 'difficulty') {
      sortedEnemies = [...baseEnemies].sort((a, b) => {
        const diffA = difficultyOrder[(a.difficulty || '').toLowerCase()] || 0;
        const diffB = difficultyOrder[(b.difficulty || '').toLowerCase()] || 0;
        return diffA !== diffB ? diffA - diffB : a.name.localeCompare(b.name);
      });
    } else {
      sortedEnemies = [...baseEnemies].sort((a, b) => a.name.localeCompare(b.name));
    }

    content.innerHTML = `
      <!-- Left side: Enemy grid (8 per row) -->
      <div id="enemies-grid-container" style="flex: 2; overflow-y: auto; padding: 10px;">
        <!-- Sort controls -->
        <div style="display: flex; gap: 10px; margin-bottom: 15px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center;">
          <span style="color: #aaa; font-size: 13px; font-weight: bold;">Sort:</span>
          <button onclick="sortEnemies('name')" id="enemy-sort-name" style="padding: 6px 12px; background: ${window.enemySortType === 'name' ? '#f44336' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Name</button>
          <button onclick="sortEnemies('type')" id="enemy-sort-type" style="padding: 6px 12px; background: ${window.enemySortType === 'type' ? '#f44336' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Type</button>
          <button onclick="sortEnemies('game')" id="enemy-sort-game" style="padding: 6px 12px; background: ${window.enemySortType === 'game' ? '#f44336' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Game</button>
          <button onclick="sortEnemies('difficulty')" id="enemy-sort-difficulty" style="padding: 6px 12px; background: ${window.enemySortType === 'difficulty' ? '#f44336' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Difficulty</button>
          <span style="color: #666; font-size: 11px; margin-left: auto;">${sortedEnemies.length} enemies</span>
        </div>
        <div style="display: grid; grid-template-columns: repeat(8, 1fr); gap: 10px;">
          ${sortedEnemies.map(enemy => {
            const diffColor = getDifficultyColor(enemy.difficulty);
            return `
            <div
              class="collection-enemy-card"
              data-enemy-name="${enemy.name.replace(/"/g, '&quot;')}"
              onclick="showEnemyDetails('${enemy.name.replace(/'/g, "\\'")}')"
              style="
                background: rgba(0,0,0,0.3);
                border: 2px solid ${diffColor};
                border-radius: 8px;
                padding: 8px;
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 6px;
                transition: transform 0.2s, box-shadow 0.2s;
                cursor: pointer;
              "
              onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 4px 12px rgba(0,0,0,0.5)';"
              onmouseout="this.style.transform=''; this.style.boxShadow='';">
              <img
                src="${enemy.imageUrl || getEnemyImagePath(enemy.name)}"
                alt="${enemy.name}"
                onerror="this.style.opacity='0.3'"
                style="
                  width: 100%;
                  height: 80px;
                  object-fit: contain;
                  border-radius: 4px;
                  background: rgba(0,0,0,0.2);
                  image-rendering: pixelated;
                  image-rendering: crisp-edges;
                "
              />
              <div style="text-align: center; font-size: 11px; font-weight: bold; color: #ddd; word-wrap: break-word; width: 100%; line-height: 1.2;">
                ${enemy.name}
              </div>
              <div style="font-size: 9px; color: ${diffColor}; text-align: center; text-transform: uppercase; font-weight: bold;">
                ${enemy.difficulty || 'Unknown'}
              </div>
            </div>
          `;}).join('')}
        </div>
      </div>

      <!-- Right side: Enemy details -->
      <div id="enemy-details" style="flex: 1; overflow-y: auto; padding: 20px; background: rgba(0,0,0,0.2); border: 1px solid #444; border-radius: 8px; min-width: 350px;">
        <div style="text-align: center; color: #888; padding: 40px 20px;">
          <p>Click an enemy to view details</p>
        </div>
      </div>
    `;
  } else if (tab === 'curses') {
    // Group curses by base name (without I, II, III)
    const curseGroups = new Map();

    curses.forEach(curse => {
      // Extract base name and tier
      const match = curse.name.match(/^(.+?)\s+(I{1,3})$/);
      if (match) {
        const baseName = match[1];
        const tier = match[2];

        if (!curseGroups.has(baseName)) {
          curseGroups.set(baseName, {});
        }
        curseGroups.get(baseName)[tier] = curse;
      }
    });

    // Sort curse groups alphabetically by base name
    const sortedGroups = Array.from(curseGroups.entries()).sort((a, b) => a[0].localeCompare(b[0]));

    // Store curse data globally for tier switching
    window.allCurseData = {};
    sortedGroups.forEach(([baseName, tiers], index) => {
      window.allCurseData[index] = tiers;
    });

    content.innerHTML = `
      <div style="flex: 1; overflow-y: auto; padding: 10px;">
        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 20px;">
          ${sortedGroups.map(([baseName, tiers], index) => {
            const firstTier = tiers['I'] || tiers['II'] || tiers['III'];
            return `
            <div style="display: flex; flex-direction: column;">
              <!-- Tier tabs above the box -->
              <div style="display: flex; gap: 3px; justify-content: center; margin-bottom: -1px; z-index: 1; position: relative;">
                ${['I', 'II', 'III'].map(tier => tiers[tier] ? `
                  <button
                    onclick="switchCurseTier(${index}, '${tier}')"
                    id="curse-${index}-tab-${tier}"
                    style="
                      padding: 5px 14px;
                      background: ${tier === 'I' ? 'rgba(0,0,0,0.3)' : '#555'};
                      border: 1px solid ${tier === 'I' ? '#9c27b0' : '#444'};
                      border-bottom: ${tier === 'I' ? '1px solid rgba(0,0,0,0.3)' : '1px solid #444'};
                      border-radius: 6px 6px 0 0;
                      color: ${tier === 'I' ? '#9c27b0' : '#aaa'};
                      cursor: pointer;
                      font-size: 11px;
                      font-weight: bold;
                      transition: all 0.2s;
                    ">
                    ${tier}
                  </button>
                ` : '').join('')}
              </div>

              <!-- Curse card box -->
              <div id="curse-card-${index}" style="
                background: rgba(0,0,0,0.3);
                border: 1px solid #444;
                border-radius: 0 8px 8px 8px;
                padding: 15px;
                display: flex;
                flex-direction: column;
                gap: 8px;
                transition: transform 0.2s, border-color 0.2s;
                position: relative;
                z-index: 0;
              " onmouseover="this.style.borderColor='#9c27b0';" onmouseout="this.style.borderColor='#444';">
                <div style="text-align: center; font-size: 13px; font-weight: bold; color: #ddd; word-wrap: break-word;">
                  ${baseName}
                </div>

                <!-- Curse details (tier I shown by default) -->
                <div id="curse-${index}-details">
                  <div style="font-size: 11px; color: #9c27b0; text-align: center;">
                    ${firstTier.stat} • ${firstTier.power}
                  </div>
                  <div style="font-size: 10px; color: #888; text-align: center;">
                    ${firstTier.duration}
                  </div>
                  <div style="font-size: 10px; color: #aaa; text-align: center; line-height: 1.4; margin-top: 5px; padding-top: 8px; border-top: 1px solid #444;">
                    ${firstTier.description}
                  </div>
                </div>
              </div>
            </div>
          `;}).join('')}
        </div>
      </div>
    `;
  }
}

// Switch between loot sub-tabs
function switchLootSubTab(subTab, sortType = null) {
  window.currentLootSubTab = subTab;

  // Initialize or preserve sort type
  if (!window.currentFishSortType) {
    window.currentFishSortType = 'alphabetical';
  }
  if (sortType) {
    window.currentFishSortType = sortType;
  }

  // Update sub-tab buttons
  const subTabBtn = document.getElementById(`loot-subtab-${subTab}`);
  if (subTabBtn) {
    // Reset all sub-tab buttons
    ['fish'].forEach(t => {
      const btn = document.getElementById(`loot-subtab-${t}`);
      if (btn) {
        btn.style.background = t === subTab ? '#66b3ff' : '#555';
      }
    });
  }

  const subTabContent = document.getElementById('loot-subtab-content');
  if (!subTabContent) return;

  if (subTab === 'fish') {
    // Get fish stats for catch counts
    const fishStats = getFishStats();

    // Sort fish based on current sort type
    let sortedFish;
    const currentSort = window.currentFishSortType;

    if (currentSort === 'rarity') {
      const rarityOrder = { 'Rare': 3, 'Uncommon': 2, 'Common': 1 };
      sortedFish = [...FISH_DATA].sort((a, b) => {
        const rarityDiff = (rarityOrder[b.rarity] || 0) - (rarityOrder[a.rarity] || 0);
        if (rarityDiff !== 0) return rarityDiff;
        return a.name.localeCompare(b.name);
      });
    } else if (currentSort === 'game') {
      sortedFish = [...FISH_DATA].sort((a, b) => {
        const gameDiff = a.game.localeCompare(b.game);
        if (gameDiff !== 0) return gameDiff;
        return a.name.localeCompare(b.name);
      });
    } else if (currentSort === 'caught') {
      sortedFish = [...FISH_DATA].sort((a, b) => {
        const aCount = (fishStats[a.name]?.caught || 0);
        const bCount = (fishStats[b.name]?.caught || 0);
        const countDiff = bCount - aCount;
        if (countDiff !== 0) return countDiff;
        return a.name.localeCompare(b.name);
      });
    } else {
      // Default: alphabetical
      sortedFish = [...FISH_DATA].sort((a, b) => a.name.localeCompare(b.name));
    }

    subTabContent.innerHTML = `
      <div style="padding: 10px;">
        <!-- Sorting controls -->
        <div style="display: flex; gap: 8px; margin-bottom: 15px; justify-content: center; flex-wrap: wrap;">
          <button onclick="switchLootSubTab('fish', 'alphabetical')" style="padding: 6px 12px; background: ${currentSort === 'alphabetical' ? '#66b3ff' : '#555'}; border: none; border-radius: 4px; color: white; cursor: pointer; font-size: 12px; font-weight: bold; transition: background 0.2s;">A-Z</button>
          <button onclick="switchLootSubTab('fish', 'rarity')" style="padding: 6px 12px; background: ${currentSort === 'rarity' ? '#66b3ff' : '#555'}; border: none; border-radius: 4px; color: white; cursor: pointer; font-size: 12px; font-weight: bold; transition: background 0.2s;">Rarity</button>
          <button onclick="switchLootSubTab('fish', 'game')" style="padding: 6px 12px; background: ${currentSort === 'game' ? '#66b3ff' : '#555'}; border: none; border-radius: 4px; color: white; cursor: pointer; font-size: 12px; font-weight: bold; transition: background 0.2s;">Game</button>
          <button onclick="switchLootSubTab('fish', 'caught')" style="padding: 6px 12px; background: ${currentSort === 'caught' ? '#66b3ff' : '#555'}; border: none; border-radius: 4px; color: white; cursor: pointer; font-size: 12px; font-weight: bold; transition: background 0.2s;"># Caught</button>
        </div>

        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 15px;">
          ${sortedFish.map(fish => {
            const stats = fishStats[fish.name] || { caught: 0, sizes: { Small: 0, Medium: 0, Large: 0 } };
            const caughtCount = stats.caught || 0;
            const sizes = stats.sizes || { Small: 0, Medium: 0, Large: 0 };

            let rarityColor = '#aaa';
            if (fish.rarity === 'Rare') rarityColor = '#ffd700';
            else if (fish.rarity === 'Uncommon') rarityColor = '#66ddff';
            else if (fish.rarity === 'Common') rarityColor = '#aaa';

            return `
              <div style="
                background: rgba(0,0,0,0.3);
                border: 2px solid ${rarityColor};
                border-radius: 8px;
                padding: 15px;
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 8px;
                transition: transform 0.2s, box-shadow 0.2s;
                position: relative;
              " onmouseover="this.style.transform='translateY(-5px)'; this.style.boxShadow='0 0 20px ${rarityColor}80';" onmouseout="this.style.transform=''; this.style.boxShadow='';">

                <!-- Caught count badge -->
                <div style="
                  position: absolute;
                  top: 10px;
                  right: 10px;
                  background: linear-gradient(135deg, #667eea, #764ba2);
                  border: 2px solid #fff;
                  border-radius: 50%;
                  width: 40px;
                  height: 40px;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  font-weight: bold;
                  font-size: 14px;
                  color: #fff;
                  box-shadow: 0 2px 8px rgba(0,0,0,0.3);
                ">
                  ${caughtCount}
                </div>

                <!-- Fish image -->
                <img
                  src="images/fish/${fish.image}.png"
                  alt="${fish.name}"
                  style="
                    width: 120px;
                    height: 120px;
                    object-fit: contain;
                    border-radius: 6px;
                  "
                  onerror="this.style.display='none';"
                />

                <!-- Fish name -->
                <div style="text-align: center; font-size: 14px; font-weight: bold; color: ${rarityColor}; word-wrap: break-word;">
                  ${fish.name}
                </div>

                <!-- Rarity -->
                <div style="font-size: 11px; color: ${rarityColor}; text-align: center; text-transform: uppercase; font-weight: bold;">
                  ${fish.rarity}
                </div>

                <!-- Game reference -->
                <div style="font-size: 10px; color: #888; text-align: center; font-style: italic;">
                  ${fish.game}
                </div>

                <!-- Location type -->
                <div style="font-size: 10px; color: #aaa; text-align: center;">
                  ${fish.type} Waters
                </div>

                <!-- Times caught text -->
                <div style="font-size: 11px; color: #ddd; text-align: center; margin-top: 5px; padding-top: 8px; border-top: 1px solid #444; width: 100%;">
                  ${caughtCount === 0 ? 'Not yet caught' : caughtCount === 1 ? 'Caught once' : `Caught ${caughtCount} times`}
                </div>

                <!-- Size breakdown -->
                ${caughtCount > 0 ? `
                  <div style="width: 100%; padding: 8px 0; border-top: 1px solid #444; display: flex; justify-content: space-around; font-size: 10px; color: #bbb;">
                    <div style="text-align: center;">
                      <div style="color: #88ff88; font-weight: bold;">S</div>
                      <div>${sizes.Small || 0}</div>
                    </div>
                    <div style="text-align: center;">
                      <div style="color: #ffdd88; font-weight: bold;">M</div>
                      <div>${sizes.Medium || 0}</div>
                    </div>
                    <div style="text-align: center;">
                      <div style="color: #ff8888; font-weight: bold;">L</div>
                      <div>${sizes.Large || 0}</div>
                    </div>
                  </div>
                ` : ''}
              </div>
            `;
          }).join('')}
        </div>
      </div>
    `;
  }
}

// Sort collection items
function sortCollectionItems(sortType) {
  // Get rarity color function (case-insensitive)
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

  // Update sort button styles
  ['alpha', 'rarity', 'game'].forEach(type => {
    const btn = document.getElementById(`sort-${type}`);
    if (btn) {
      btn.style.background = type === sortType.substring(0, type.length) || (sortType === 'alphabetical' && type === 'alpha') ? '#ff9800' : '#555';
    }
  });

  // Filter N/A items if needed
  let filteredItems = window.itemsShowNA ? [...items] : items.filter(item => {
    const rarity = (item.rarity || '').toLowerCase();
    return rarity !== 'n/a';
  });

  let sortedItems;
  if (sortType === 'alphabetical') {
    sortedItems = filteredItems.sort((a, b) => a.name.localeCompare(b.name));
  } else if (sortType === 'rarity') {
    const rarityOrder = { 'legendary': 4, 'rare': 3, 'uncommon': 2, 'common': 1 };
    sortedItems = filteredItems.sort((a, b) => {
      const rarityDiff = (rarityOrder[(b.rarity || '').toLowerCase()] || 0) - (rarityOrder[(a.rarity || '').toLowerCase()] || 0);
      if (rarityDiff !== 0) return rarityDiff;
      return a.name.localeCompare(b.name);
    });
  } else if (sortType === 'game') {
    sortedItems = filteredItems.sort((a, b) => {
      const gameA = a.game || 'Unknown';
      const gameB = b.game || 'Unknown';
      const gameDiff = gameA.localeCompare(gameB);
      if (gameDiff !== 0) return gameDiff;
      return a.name.localeCompare(b.name);
    });
  }

  // Update the grid
  const grid = document.getElementById('items-grid');
  if (grid) {
    grid.innerHTML = sortedItems.map(item => {
      const rarityColor = getRarityColor(item.rarity);
      return `
        <div style="
          background: rgba(0,0,0,0.3);
          border: 2px solid ${rarityColor};
          border-radius: 8px;
          padding: 10px;
          display: flex;
          flex-direction: column;
          gap: 8px;
          transition: transform 0.2s, box-shadow 0.2s;
        " onmouseover="this.style.transform='translateY(-5px)'; this.style.boxShadow='0 8px 20px rgba(${rarityColor === '#ff6b00' ? '255,107,0' : rarityColor === '#9b59b6' ? '155,89,182' : rarityColor === '#4CAF50' ? '76,175,80' : '170,170,170'}, 0.4)';" onmouseout="this.style.transform=''; this.style.boxShadow='';">
          <img
            src="${item.image || 'images/items/no-item.svg'}"
            alt="${item.name}"
            style="
              width: 100%;
              height: 120px;
              object-fit: contain;
              border-radius: 6px;
              background: rgba(0,0,0,0.2);
              image-rendering: pixelated;
            "
            onerror="this.style.display='none';"
          />
          <div style="text-align: center; font-size: 12px; font-weight: bold; color: ${rarityColor}; word-wrap: break-word;">
            ${item.name}
          </div>
          <div style="font-size: 10px; color: ${rarityColor}; text-align: center; text-transform: uppercase; font-weight: bold;">
            ${item.rarity}
          </div>
          <div style="font-size: 10px; color: #888; text-align: center; font-style: italic;">
            ${item.game || 'Unknown'}
          </div>
          <div style="font-size: 10px; color: #aaa; text-align: center; line-height: 1.4;">
            ${item.description || 'No description'}
          </div>
        </div>
      `;
    }).join('');
  }
}

// Toggle N/A items visibility
function toggleItemsNA() {
  window.itemsShowNA = !window.itemsShowNA;
  switchCollectionTab('items');
}

// Sort enemies in collection
function sortEnemies(sortType) {
  window.enemySortType = sortType;
  switchCollectionTab('enemies');
}

// Switch between curse tiers (I, II, III)
function switchCurseTier(cardIndex, tier) {
  if (!window.allCurseData || !window.allCurseData[cardIndex]) {
    console.error('Curse data not found for card', cardIndex);
    return;
  }

  const tiersData = window.allCurseData[cardIndex];
  if (!tiersData[tier]) {
    console.error('Tier not found:', tier);
    return;
  }

  const curse = tiersData[tier];
  const detailsDiv = document.getElementById(`curse-${cardIndex}-details`);

  if (detailsDiv) {
    detailsDiv.innerHTML = `
      <div style="font-size: 11px; color: #9c27b0; text-align: center;">
        ${curse.stat} • ${curse.power}
      </div>
      <div style="font-size: 10px; color: #888; text-align: center;">
        ${curse.duration}
      </div>
      <div style="font-size: 10px; color: #aaa; text-align: center; line-height: 1.4; margin-top: 5px; padding-top: 8px; border-top: 1px solid #444;">
        ${curse.description}
      </div>
    `;
  }

  // Update tab button styles
  ['I', 'II', 'III'].forEach(t => {
    const tabBtn = document.getElementById(`curse-${cardIndex}-tab-${t}`);
    if (tabBtn) {
      const isActive = t === tier;
      tabBtn.style.background = isActive ? 'rgba(0,0,0,0.3)' : '#555';
      tabBtn.style.borderColor = isActive ? '#9c27b0' : '#444';
      tabBtn.style.borderBottomColor = isActive ? 'rgba(0,0,0,0.3)' : '#444';
      tabBtn.style.color = isActive ? '#9c27b0' : '#aaa';
    }
  });
}

// Export escape phase functions globally
window.switchCurseTier = switchCurseTier;
window.switchLootSubTab = switchLootSubTab;
window.completeEscapeGame = completeEscapeGame;
window.recordLostRun = recordLostRun;
window.startEscapePhase = startEscapePhase;
window.showVictoryScreen = showVictoryScreen;
window.sortCollectionItems = sortCollectionItems;
