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
      <div style="display: flex; gap: 8px; margin-bottom: 15px; padding-bottom: 10px; border-bottom: 2px solid #444; align-items: center; flex-wrap: wrap;">
        <h2 style="color: #ff9800; margin: 0; flex: 1; min-width: 120px;">📚 Collection</h2>
        <button onclick="switchCollectionTab('games')" id="tab-games" style="padding: 6px 12px; background: #ff9800; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Games (${games.length})</button>
        <button onclick="switchCollectionTab('characters')" id="tab-characters" style="padding: 6px 12px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Characters (${typeof CHARACTERS_DATA !== 'undefined' ? CHARACTERS_DATA.length : 0})</button>
        <button onclick="switchCollectionTab('items')" id="tab-items" style="padding: 6px 12px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Items (${items.length})</button>
        <button onclick="switchCollectionTab('loot')" id="tab-loot" style="padding: 6px 12px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Loot</button>
        <button onclick="switchCollectionTab('enemies')" id="tab-enemies" style="padding: 6px 12px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Enemies (${enemies.length})</button>
        <button onclick="switchCollectionTab('allies')" id="tab-allies" style="padding: 6px 12px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Allies (${typeof ALLIES_DATA !== 'undefined' ? ALLIES_DATA.length : 0})</button>
        <button onclick="switchCollectionTab('curses')" id="tab-curses" style="padding: 6px 12px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Curses (${curses.length})</button>
        <button onclick="switchCollectionTab('statuses')" id="tab-statuses" style="padding: 6px 12px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Statuses (${typeof STATUSES_DATA !== 'undefined' ? STATUSES_DATA.length : 0})</button>
        <button onclick="switchCollectionTab('spells')" id="tab-spells" style="padding: 6px 12px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Spells (${typeof SPELLS_DATA !== 'undefined' ? SPELLS_DATA.length : 0})</button>
        <button onclick="closeGameModal();" style="padding: 6px 14px; background: #444; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Close</button>
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
  const tabs = ['games', 'characters', 'items', 'loot', 'enemies', 'allies', 'curses', 'statuses', 'spells'];
  tabs.forEach(t => {
    const btn = document.getElementById(`tab-${t}`);
    if (btn) {
      btn.style.background = t === tab ? '#ff9800' : '#555';
    }
  });

  const content = document.getElementById('collection-content');
  if (!content) return;

  if (tab === 'games') {
    // Initialize search state
    if (typeof window.gamesSearchTerm === 'undefined') window.gamesSearchTerm = '';

    // Filter and sort games
    const searchTerm = window.gamesSearchTerm.toLowerCase();
    let filteredGames = searchTerm
      ? games.filter(g => g.name.toLowerCase().includes(searchTerm))
      : [...games];
    const sortedGames = filteredGames.sort((a, b) => a.name.localeCompare(b.name));

    // Get game stats for amulet icons
    const allStats = getGameStats();

    content.innerHTML = `
      <!-- Left side: Game grid -->
      <div id="games-grid" style="flex: 2; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
        <!-- Search bar -->
        <div style="display: flex; gap: 10px; margin-bottom: 15px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center;">
          <span style="color: #aaa; font-size: 13px;">🔍</span>
          <input type="text" id="games-search" placeholder="Search games..." value="${window.gamesSearchTerm}"
            oninput="window.gamesSearchTerm = this.value; switchCollectionTab('games');"
            style="flex: 1; padding: 8px 12px; background: rgba(0,0,0,0.3); border: 1px solid #555; border-radius: 6px; color: white; font-size: 13px; outline: none;"
          />
          <span style="color: #666; font-size: 11px;">${sortedGames.length} of ${games.length}</span>
        </div>
        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 15px; overflow-y: auto;">
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
  } else if (tab === 'characters') {
    // Initialize search and sort state
    if (typeof window.charactersSearchTerm === 'undefined') window.charactersSearchTerm = '';
    if (!window.characterSortType) window.characterSortType = 'alphabetical';

    const charactersData = typeof CHARACTERS_DATA !== 'undefined' ? CHARACTERS_DATA : [];
    const searchTerm = window.charactersSearchTerm.toLowerCase();

    // Filter by search
    let filteredCharacters = searchTerm
      ? charactersData.filter(c => c.name.toLowerCase().includes(searchTerm) || (c.game && c.game.toLowerCase().includes(searchTerm)))
      : [...charactersData];

    // Sort characters
    let sortedCharacters;
    if (window.characterSortType === 'alphabetical') {
      sortedCharacters = filteredCharacters.sort((a, b) => a.name.localeCompare(b.name));
    } else if (window.characterSortType === 'game') {
      sortedCharacters = filteredCharacters.sort((a, b) => {
        const gameDiff = (a.game || '').localeCompare(b.game || '');
        return gameDiff !== 0 ? gameDiff : a.name.localeCompare(b.name);
      });
    } else {
      sortedCharacters = filteredCharacters.sort((a, b) => a.name.localeCompare(b.name));
    }

    content.innerHTML = `
      <!-- Left side: Character grid -->
      <div id="characters-grid-container" style="flex: 2; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
        <!-- Search and Sort controls -->
        <div style="display: flex; gap: 10px; margin-bottom: 15px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center; flex-wrap: wrap;">
          <span style="color: #aaa; font-size: 13px;">🔍</span>
          <input type="text" id="characters-search" placeholder="Search characters..." value="${window.charactersSearchTerm}"
            oninput="window.charactersSearchTerm = this.value; switchCollectionTab('characters');"
            style="flex: 1; min-width: 150px; padding: 8px 12px; background: rgba(0,0,0,0.3); border: 1px solid #555; border-radius: 6px; color: white; font-size: 13px; outline: none;"
          />
          <div style="border-left: 1px solid #555; height: 20px; margin: 0 5px;"></div>
          <span style="color: #aaa; font-size: 13px; font-weight: bold;">Sort:</span>
          <button onclick="window.characterSortType = 'alphabetical'; switchCollectionTab('characters');" style="padding: 6px 12px; background: ${window.characterSortType === 'alphabetical' ? '#4CAF50' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">A-Z</button>
          <button onclick="window.characterSortType = 'game'; switchCollectionTab('characters');" style="padding: 6px 12px; background: ${window.characterSortType === 'game' ? '#4CAF50' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Game</button>
          <span style="color: #666; font-size: 11px; margin-left: auto;">${sortedCharacters.length} of ${charactersData.length}</span>
        </div>

        <div id="characters-grid" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 12px; overflow-y: auto;">
          ${sortedCharacters.map(char => {
            const charIcon = `images/characters/${char.name}.png`;
            return `
            <div
              class="collection-character-card"
              data-character-name="${char.name.replace(/"/g, '&quot;')}"
              onclick="showCharacterDetails('${char.name.replace(/'/g, "\\'")}')"
              style="
                background: rgba(0,0,0,0.3);
                border: 2px solid #4CAF50;
                border-radius: 8px;
                padding: 10px;
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 6px;
                transition: transform 0.2s, box-shadow 0.2s;
                cursor: pointer;
              "
              onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 6px 15px rgba(0,0,0,0.5)';"
              onmouseout="this.style.transform=''; this.style.boxShadow='';"
            >
              <img
                src="${charIcon}"
                alt="${char.name}"
                style="
                  width: 80px;
                  height: 80px;
                  object-fit: contain;
                  border-radius: 6px;
                  background: rgba(0,0,0,0.2);
                  image-rendering: pixelated;
                "
                onerror="this.style.opacity='0.3';"
              />
              <div style="text-align: center; font-size: 12px; font-weight: bold; color: #4CAF50; word-wrap: break-word; width: 100%;">
                ${char.name}
              </div>
              <div style="font-size: 10px; color: #888; text-align: center;">
                ${char.game || 'Unknown'}
              </div>
            </div>
          `;
          }).join('')}
        </div>
      </div>

      <!-- Right side: Character details -->
      <div id="character-details" style="flex: 1; overflow-y: auto; padding: 20px; background: rgba(0,0,0,0.2); border: 1px solid #444; border-radius: 8px; min-width: 300px;">
        <div style="text-align: center; color: #888; padding: 40px 20px;">
          <p>Click a character to view details</p>
        </div>
      </div>
    `;
  } else if (tab === 'items') {
    // Initialize filter state if not set
    if (typeof window.itemsShowNA === 'undefined') window.itemsShowNA = false;
    if (typeof window.itemsSearchTerm === 'undefined') window.itemsSearchTerm = '';
    if (typeof window.itemsTypeFilter === 'undefined') window.itemsTypeFilter = 'all';
    if (!window.itemsSortType) window.itemsSortType = 'alphabetical';

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

    // Get unique item types
    const itemTypes = [...new Set(items.map(i => i.type).filter(t => t))].sort();

    // Filter items
    let filteredItems = [...items];

    // Filter by N/A
    if (!window.itemsShowNA) {
      filteredItems = filteredItems.filter(item => (item.rarity || '').toLowerCase() !== 'n/a');
    }

    // Filter by search term
    const searchTerm = window.itemsSearchTerm.toLowerCase();
    if (searchTerm) {
      filteredItems = filteredItems.filter(item =>
        item.name.toLowerCase().includes(searchTerm) ||
        (item.description && item.description.toLowerCase().includes(searchTerm)) ||
        (item.game && item.game.toLowerCase().includes(searchTerm))
      );
    }

    // Filter by type
    if (window.itemsTypeFilter !== 'all') {
      filteredItems = filteredItems.filter(item => item.type === window.itemsTypeFilter);
    }

    // Sort items
    let sortedItems;
    if (window.itemsSortType === 'alphabetical') {
      sortedItems = filteredItems.sort((a, b) => a.name.localeCompare(b.name));
    } else if (window.itemsSortType === 'rarity') {
      const rarityOrder = { 'legendary': 4, 'rare': 3, 'uncommon': 2, 'common': 1 };
      sortedItems = filteredItems.sort((a, b) => {
        const rarityDiff = (rarityOrder[(b.rarity || '').toLowerCase()] || 0) - (rarityOrder[(a.rarity || '').toLowerCase()] || 0);
        return rarityDiff !== 0 ? rarityDiff : a.name.localeCompare(b.name);
      });
    } else if (window.itemsSortType === 'game') {
      sortedItems = filteredItems.sort((a, b) => {
        const gameA = a.game || 'Unknown';
        const gameB = b.game || 'Unknown';
        const gameDiff = gameA.localeCompare(gameB);
        return gameDiff !== 0 ? gameDiff : a.name.localeCompare(b.name);
      });
    } else {
      sortedItems = filteredItems.sort((a, b) => a.name.localeCompare(b.name));
    }

    const naCount = items.filter(item => (item.rarity || '').toLowerCase() === 'n/a').length;

    content.innerHTML = `
      <!-- Left side: Item grid -->
      <div id="items-grid-container" style="flex: 2; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
        <!-- Search, Sort and Filter controls -->
        <div style="display: flex; gap: 8px; margin-bottom: 15px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center; flex-wrap: wrap;">
          <span style="color: #aaa; font-size: 13px;">🔍</span>
          <input type="text" id="items-search" placeholder="Search items..." value="${window.itemsSearchTerm}"
            oninput="window.itemsSearchTerm = this.value; switchCollectionTab('items');"
            style="flex: 1; min-width: 120px; padding: 6px 10px; background: rgba(0,0,0,0.3); border: 1px solid #555; border-radius: 6px; color: white; font-size: 12px; outline: none;"
          />
          <div style="border-left: 1px solid #555; height: 20px; margin: 0 3px;"></div>
          <span style="color: #aaa; font-size: 12px; font-weight: bold;">Sort:</span>
          <button onclick="window.itemsSortType = 'alphabetical'; switchCollectionTab('items');" style="padding: 5px 10px; background: ${window.itemsSortType === 'alphabetical' ? '#ff9800' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">A-Z</button>
          <button onclick="window.itemsSortType = 'rarity'; switchCollectionTab('items');" style="padding: 5px 10px; background: ${window.itemsSortType === 'rarity' ? '#ff9800' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">Rarity</button>
          <button onclick="window.itemsSortType = 'game'; switchCollectionTab('items');" style="padding: 5px 10px; background: ${window.itemsSortType === 'game' ? '#ff9800' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">Game</button>
          <div style="border-left: 1px solid #555; height: 20px; margin: 0 3px;"></div>
          <span style="color: #aaa; font-size: 12px; font-weight: bold;">Type:</span>
          <select onchange="window.itemsTypeFilter = this.value; switchCollectionTab('items');" style="padding: 5px 8px; background: #444; border: 1px solid #555; border-radius: 6px; color: white; font-size: 11px; cursor: pointer;">
            <option value="all" ${window.itemsTypeFilter === 'all' ? 'selected' : ''}>All</option>
            ${itemTypes.map(type => `<option value="${type}" ${window.itemsTypeFilter === type ? 'selected' : ''}>${type}</option>`).join('')}
          </select>
          <button onclick="toggleItemsNA()" style="padding: 5px 10px; background: ${window.itemsShowNA ? '#ff9800' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">
            N/A (${naCount})
          </button>
          <span style="color: #666; font-size: 10px; margin-left: auto;">${sortedItems.length} of ${items.length}</span>
        </div>

        <div id="items-grid" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 10px; overflow-y: auto;">
          ${sortedItems.map(item => {
            const rarityColor = getRarityColor(item.rarity);
            return `
            <div
              class="collection-item-card"
              data-item-name="${item.name.replace(/"/g, '&quot;')}"
              onclick="showItemDetails('${item.name.replace(/'/g, "\\'")}')"
              style="
                background: rgba(0,0,0,0.3);
                border: 2px solid ${rarityColor};
                border-radius: 8px;
                padding: 8px;
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 6px;
                transition: transform 0.2s, box-shadow 0.2s;
                cursor: pointer;
              "
              onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 6px 15px rgba(0,0,0,0.5)';"
              onmouseout="this.style.transform=''; this.style.boxShadow='';"
            >
              <img
                src="${item.image || 'images/items/no-item.svg'}"
                alt="${item.name}"
                style="
                  width: 80px;
                  height: 80px;
                  object-fit: contain;
                  border-radius: 6px;
                  background: rgba(0,0,0,0.2);
                  image-rendering: pixelated;
                "
                onerror="this.style.display='none';"
              />
              <div style="text-align: center; font-size: 11px; font-weight: bold; color: ${rarityColor}; word-wrap: break-word; width: 100%;">
                ${item.name}
              </div>
              <div style="font-size: 9px; color: ${rarityColor}; text-align: center; text-transform: uppercase; font-weight: bold;">
                ${item.rarity}
              </div>
            </div>
          `;
          }).join('')}
        </div>
      </div>

      <!-- Right side: Item details -->
      <div id="item-details" style="flex: 1; overflow-y: auto; padding: 20px; background: rgba(0,0,0,0.2); border: 1px solid #444; border-radius: 8px; min-width: 300px;">
        <div style="text-align: center; color: #888; padding: 40px 20px;">
          <p>Click an item to view details</p>
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
    const baseEnemies = enemies.filter(e => !e.variantOf);

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
  } else if (tab === 'allies') {
    // Initialize search state
    if (typeof window.alliesSearchTerm === 'undefined') window.alliesSearchTerm = '';
    if (!window.allySortType) window.allySortType = 'alphabetical';

    const alliesData = typeof ALLIES_DATA !== 'undefined' ? ALLIES_DATA : [];
    const searchTerm = window.alliesSearchTerm.toLowerCase();

    // Filter by search
    let filteredAllies = searchTerm
      ? alliesData.filter(a => a.name.toLowerCase().includes(searchTerm) || (a.game && a.game.toLowerCase().includes(searchTerm)))
      : [...alliesData];

    // Sort allies
    let sortedAllies;
    if (window.allySortType === 'alphabetical') {
      sortedAllies = filteredAllies.sort((a, b) => a.name.localeCompare(b.name));
    } else if (window.allySortType === 'game') {
      sortedAllies = filteredAllies.sort((a, b) => {
        const gameDiff = (a.game || '').localeCompare(b.game || '');
        return gameDiff !== 0 ? gameDiff : a.name.localeCompare(b.name);
      });
    } else if (window.allySortType === 'rarity') {
      const rarityOrder = { 'high': 3, 'medium': 2, 'low': 1 };
      sortedAllies = filteredAllies.sort((a, b) => {
        const rarityDiff = (rarityOrder[(b.rarity || '').toLowerCase()] || 0) - (rarityOrder[(a.rarity || '').toLowerCase()] || 0);
        return rarityDiff !== 0 ? rarityDiff : a.name.localeCompare(b.name);
      });
    } else {
      sortedAllies = filteredAllies.sort((a, b) => a.name.localeCompare(b.name));
    }

    // Get rarity color
    const getAllyRarityColor = (rarity) => {
      switch((rarity || '').toLowerCase()) {
        case 'high': return '#9b59b6';
        case 'medium': return '#ff9800';
        case 'low': return '#4CAF50';
        default: return '#888';
      }
    };

    content.innerHTML = `
      <!-- Left side: Ally grid -->
      <div id="allies-grid-container" style="flex: 2; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
        <!-- Search and Sort controls -->
        <div style="display: flex; gap: 10px; margin-bottom: 15px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center; flex-wrap: wrap;">
          <span style="color: #aaa; font-size: 13px;">🔍</span>
          <input type="text" id="allies-search" placeholder="Search allies..." value="${window.alliesSearchTerm}"
            oninput="window.alliesSearchTerm = this.value; switchCollectionTab('allies');"
            style="flex: 1; min-width: 150px; padding: 8px 12px; background: rgba(0,0,0,0.3); border: 1px solid #555; border-radius: 6px; color: white; font-size: 13px; outline: none;"
          />
          <div style="border-left: 1px solid #555; height: 20px; margin: 0 5px;"></div>
          <span style="color: #aaa; font-size: 13px; font-weight: bold;">Sort:</span>
          <button onclick="window.allySortType = 'alphabetical'; switchCollectionTab('allies');" style="padding: 6px 12px; background: ${window.allySortType === 'alphabetical' ? '#2196F3' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">A-Z</button>
          <button onclick="window.allySortType = 'game'; switchCollectionTab('allies');" style="padding: 6px 12px; background: ${window.allySortType === 'game' ? '#2196F3' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Game</button>
          <button onclick="window.allySortType = 'rarity'; switchCollectionTab('allies');" style="padding: 6px 12px; background: ${window.allySortType === 'rarity' ? '#2196F3' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Rarity</button>
          <span style="color: #666; font-size: 11px; margin-left: auto;">${sortedAllies.length} of ${alliesData.length}</span>
        </div>

        <div id="allies-grid" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 12px; overflow-y: auto;">
          ${sortedAllies.map(ally => {
            const allyIcon = ally.image || `images/allies/${ally.name}.png`;
            const rarityColor = getAllyRarityColor(ally.rarity);
            return `
            <div
              class="collection-ally-card"
              data-ally-name="${ally.name.replace(/"/g, '&quot;')}"
              onclick="showAllyDetails('${ally.name.replace(/'/g, "\\'")}')"
              style="
                background: rgba(0,0,0,0.3);
                border: 2px solid ${rarityColor};
                border-radius: 8px;
                padding: 10px;
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 6px;
                transition: transform 0.2s, box-shadow 0.2s;
                cursor: pointer;
              "
              onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 6px 15px rgba(0,0,0,0.5)';"
              onmouseout="this.style.transform=''; this.style.boxShadow='';"
            >
              <img
                src="${allyIcon}"
                alt="${ally.name}"
                style="
                  width: 80px;
                  height: 80px;
                  object-fit: contain;
                  border-radius: 6px;
                  background: rgba(0,0,0,0.2);
                  image-rendering: pixelated;
                "
                onerror="this.style.opacity='0.3';"
              />
              <div style="text-align: center; font-size: 12px; font-weight: bold; color: ${rarityColor}; word-wrap: break-word; width: 100%;">
                ${ally.name}
              </div>
              <div style="font-size: 10px; color: #888; text-align: center;">
                ${ally.type || 'Ally'} • HP: ${ally.hp || '?'}
              </div>
              <div style="font-size: 9px; color: #666; text-align: center;">
                ${ally.game || 'Unknown'}
              </div>
            </div>
          `;
          }).join('')}
        </div>
      </div>

      <!-- Right side: Ally details -->
      <div id="ally-details" style="flex: 1; overflow-y: auto; padding: 20px; background: rgba(0,0,0,0.2); border: 1px solid #444; border-radius: 8px; min-width: 300px;">
        <div style="text-align: center; color: #888; padding: 40px 20px;">
          <p>Click an ally to view details</p>
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
  } else if (tab === 'statuses') {
    // Initialize search and filter state
    if (typeof window.statusesSearchTerm === 'undefined') window.statusesSearchTerm = '';
    if (!window.statusSortType) window.statusSortType = 'alphabetical';
    if (typeof window.statusTypeFilter === 'undefined') window.statusTypeFilter = 'all';

    const statusesData = typeof STATUSES_DATA !== 'undefined' ? STATUSES_DATA : [];
    const searchTerm = window.statusesSearchTerm.toLowerCase();

    // Filter by search
    let filteredStatuses = searchTerm
      ? statusesData.filter(s => s.name.toLowerCase().includes(searchTerm) || (s.description && s.description.toLowerCase().includes(searchTerm)))
      : [...statusesData];

    // Filter by type
    if (window.statusTypeFilter !== 'all') {
      filteredStatuses = filteredStatuses.filter(s => (s.type || '').toLowerCase() === window.statusTypeFilter.toLowerCase());
    }

    // Sort statuses
    let sortedStatuses;
    if (window.statusSortType === 'alphabetical') {
      sortedStatuses = filteredStatuses.sort((a, b) => a.name.localeCompare(b.name));
    } else if (window.statusSortType === 'type') {
      sortedStatuses = filteredStatuses.sort((a, b) => {
        const typeDiff = (a.type || '').localeCompare(b.type || '');
        return typeDiff !== 0 ? typeDiff : a.name.localeCompare(b.name);
      });
    } else {
      sortedStatuses = filteredStatuses.sort((a, b) => a.name.localeCompare(b.name));
    }

    // Get status type color
    const getStatusTypeColor = (type) => {
      switch((type || '').toLowerCase()) {
        case 'buff': return '#4CAF50';
        case 'debuff': return '#f44336';
        default: return '#888';
      }
    };

    content.innerHTML = `
      <div style="flex: 1; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
        <!-- Search and Filter controls -->
        <div style="display: flex; gap: 10px; margin-bottom: 15px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center; flex-wrap: wrap;">
          <span style="color: #aaa; font-size: 13px;">🔍</span>
          <input type="text" id="statuses-search" placeholder="Search statuses..." value="${window.statusesSearchTerm}"
            oninput="window.statusesSearchTerm = this.value; switchCollectionTab('statuses');"
            style="flex: 1; min-width: 150px; padding: 8px 12px; background: rgba(0,0,0,0.3); border: 1px solid #555; border-radius: 6px; color: white; font-size: 13px; outline: none;"
          />
          <div style="border-left: 1px solid #555; height: 20px; margin: 0 5px;"></div>
          <span style="color: #aaa; font-size: 13px; font-weight: bold;">Sort:</span>
          <button onclick="window.statusSortType = 'alphabetical'; switchCollectionTab('statuses');" style="padding: 6px 12px; background: ${window.statusSortType === 'alphabetical' ? '#ff9800' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">A-Z</button>
          <button onclick="window.statusSortType = 'type'; switchCollectionTab('statuses');" style="padding: 6px 12px; background: ${window.statusSortType === 'type' ? '#ff9800' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Type</button>
          <div style="border-left: 1px solid #555; height: 20px; margin: 0 5px;"></div>
          <span style="color: #aaa; font-size: 13px; font-weight: bold;">Filter:</span>
          <button onclick="window.statusTypeFilter = 'all'; switchCollectionTab('statuses');" style="padding: 6px 12px; background: ${window.statusTypeFilter === 'all' ? '#ff9800' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">All</button>
          <button onclick="window.statusTypeFilter = 'buff'; switchCollectionTab('statuses');" style="padding: 6px 12px; background: ${window.statusTypeFilter === 'buff' ? '#4CAF50' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Buffs</button>
          <button onclick="window.statusTypeFilter = 'debuff'; switchCollectionTab('statuses');" style="padding: 6px 12px; background: ${window.statusTypeFilter === 'debuff' ? '#f44336' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Debuffs</button>
          <span style="color: #666; font-size: 11px; margin-left: auto;">${sortedStatuses.length} of ${statusesData.length}</span>
        </div>

        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 15px; overflow-y: auto;">
          ${sortedStatuses.map(status => {
            const typeColor = getStatusTypeColor(status.type);
            const statusIcon = status.image || `images/statuses/${status.name}.png`;
            return `
            <div style="
              background: rgba(0,0,0,0.3);
              border: 2px solid ${typeColor};
              border-radius: 8px;
              padding: 15px;
              display: flex;
              gap: 12px;
              align-items: flex-start;
              transition: transform 0.2s, box-shadow 0.2s;
            " onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 6px 15px rgba(0,0,0,0.5)';" onmouseout="this.style.transform=''; this.style.boxShadow='';">
              <img
                src="${statusIcon}"
                alt="${status.name}"
                style="
                  width: 48px;
                  height: 48px;
                  object-fit: contain;
                  border-radius: 6px;
                  background: rgba(0,0,0,0.2);
                  image-rendering: pixelated;
                  flex-shrink: 0;
                "
                onerror="this.style.opacity='0.3';"
              />
              <div style="flex: 1; min-width: 0;">
                <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px;">
                  <div style="font-size: 14px; font-weight: bold; color: ${typeColor};">${status.name}</div>
                  <div style="font-size: 10px; color: ${typeColor}; text-transform: uppercase; font-weight: bold; padding: 2px 8px; background: rgba(${typeColor === '#4CAF50' ? '76,175,80' : '244,67,54'}, 0.2); border-radius: 4px;">
                    ${status.type || 'Unknown'}
                  </div>
                </div>
                <div style="font-size: 12px; color: #ddd; line-height: 1.4; margin-bottom: 8px;">
                  ${status.description || 'No description'}
                </div>
                <div style="display: flex; gap: 10px; flex-wrap: wrap; font-size: 10px; color: #888;">
                  ${status.stackable ? '<span style="color: #66b3ff;">Stackable</span>' : ''}
                  ${status.decay && status.decay !== 'None' ? `<span>Decay: ${status.decay}</span>` : ''}
                </div>
              </div>
            </div>
          `;
          }).join('')}
        </div>
      </div>
    `;
  } else if (tab === 'spells') {
    // Initialize state
    if (!window.spellSortType) window.spellSortType = 'alphabetical';
    if (typeof window.spellsSearchTerm === 'undefined') window.spellsSearchTerm = '';
    if (typeof window.spellElementFilter === 'undefined') window.spellElementFilter = 'all';
    if (typeof window.spellSubTab === 'undefined') window.spellSubTab = 'spells';

    // Get rarity color function
    const getRarityColor = (rarity) => {
      const rarityLower = (rarity || '').toLowerCase();
      switch(rarityLower) {
        case 'rare': return '#9b59b6';
        case 'uncommon': return '#4CAF50';
        case 'common': return '#aaa';
        default: return '#888';
      }
    };

    // Get element color function
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

    // Get spells and keywords data
    const spellsData = typeof SPELLS_DATA !== 'undefined' ? SPELLS_DATA : [];
    const keywordsData = typeof SPELL_KEYWORDS_DATA !== 'undefined' ? SPELL_KEYWORDS_DATA : {};
    const searchTerm = window.spellsSearchTerm.toLowerCase();

    // Get unique elements for filter
    const elements = [...new Set(spellsData.map(s => s.element).filter(e => e && e !== 'N/A'))].sort();

    // Filter spells
    let filteredSpells = [...spellsData];

    // Filter by search
    if (searchTerm) {
      filteredSpells = filteredSpells.filter(s =>
        s.name.toLowerCase().includes(searchTerm) ||
        (s.description && s.description.toLowerCase().includes(searchTerm))
      );
    }

    // Filter by element
    if (window.spellElementFilter !== 'all') {
      if (window.spellElementFilter === 'none') {
        filteredSpells = filteredSpells.filter(s => !s.element || s.element === 'N/A');
      } else {
        filteredSpells = filteredSpells.filter(s => s.element === window.spellElementFilter);
      }
    }

    // Sort spells
    let sortedSpells;
    if (window.spellSortType === 'alphabetical') {
      sortedSpells = filteredSpells.sort((a, b) => a.name.localeCompare(b.name));
    } else if (window.spellSortType === 'rarity') {
      const rarityOrder = { 'rare': 3, 'uncommon': 2, 'common': 1 };
      sortedSpells = filteredSpells.sort((a, b) => {
        const rarityDiff = (rarityOrder[(b.rarity || '').toLowerCase()] || 0) - (rarityOrder[(a.rarity || '').toLowerCase()] || 0);
        return rarityDiff !== 0 ? rarityDiff : a.name.localeCompare(b.name);
      });
    } else if (window.spellSortType === 'element') {
      sortedSpells = filteredSpells.sort((a, b) => {
        const elemA = a.element || 'N/A';
        const elemB = b.element || 'N/A';
        return elemA.localeCompare(elemB) || a.name.localeCompare(b.name);
      });
    } else if (window.spellSortType === 'cost') {
      sortedSpells = filteredSpells.sort((a, b) => (a.cost || 0) - (b.cost || 0) || a.name.localeCompare(b.name));
    } else if (window.spellSortType === 'game') {
      sortedSpells = filteredSpells.sort((a, b) => (a.game || '').localeCompare(b.game || '') || a.name.localeCompare(b.name));
    } else {
      sortedSpells = filteredSpells.sort((a, b) => a.name.localeCompare(b.name));
    }

    // Build keywords array from the object
    const keywordsArray = Object.values(keywordsData);

    if (window.spellSubTab === 'keywords') {
      // Show keywords sub-tab
      content.innerHTML = `
        <div style="flex: 1; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
          <!-- Sub-tab navigation -->
          <div style="display: flex; gap: 10px; margin-bottom: 15px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center;">
            <button onclick="window.spellSubTab = 'spells'; switchCollectionTab('spells');" style="padding: 8px 16px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 13px;">Spells (${spellsData.length})</button>
            <button onclick="window.spellSubTab = 'keywords'; switchCollectionTab('spells');" style="padding: 8px 16px; background: #9b59b6; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 13px;">Keywords (${keywordsArray.length})</button>
          </div>

          <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 15px; overflow-y: auto;">
            ${keywordsArray.map(kw => `
              <div style="
                background: rgba(0,0,0,0.3);
                border: 2px solid #9b59b6;
                border-radius: 8px;
                padding: 15px;
                display: flex;
                flex-direction: column;
                gap: 8px;
              ">
                <div style="font-size: 16px; font-weight: bold; color: #9b59b6;">${kw.name}</div>
                <div style="font-size: 13px; color: #ddd; line-height: 1.5;">${kw.description}</div>
              </div>
            `).join('')}
          </div>
        </div>
      `;
    } else {
      // Show spells sub-tab
      content.innerHTML = `
        <!-- Left side: Spell grid -->
        <div id="spells-grid-container" style="flex: 2; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
          <!-- Sub-tab navigation -->
          <div style="display: flex; gap: 10px; margin-bottom: 10px; padding: 8px 10px; background: rgba(0,0,0,0.2); border-radius: 6px; align-items: center;">
            <button onclick="window.spellSubTab = 'spells'; switchCollectionTab('spells');" style="padding: 6px 14px; background: #9b59b6; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Spells (${spellsData.length})</button>
            <button onclick="window.spellSubTab = 'keywords'; switchCollectionTab('spells');" style="padding: 6px 14px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px;">Keywords (${keywordsArray.length})</button>
          </div>

          <!-- Search, Sort and Filter controls -->
          <div style="display: flex; gap: 8px; margin-bottom: 15px; padding: 10px; background: rgba(0,0,0,0.3); border-radius: 8px; align-items: center; flex-wrap: wrap;">
            <span style="color: #aaa; font-size: 13px;">🔍</span>
            <input type="text" id="spells-search" placeholder="Search spells..." value="${window.spellsSearchTerm}"
              oninput="window.spellsSearchTerm = this.value; switchCollectionTab('spells');"
              style="flex: 1; min-width: 120px; padding: 6px 10px; background: rgba(0,0,0,0.3); border: 1px solid #555; border-radius: 6px; color: white; font-size: 12px; outline: none;"
            />
            <div style="border-left: 1px solid #555; height: 20px; margin: 0 3px;"></div>
            <span style="color: #aaa; font-size: 12px; font-weight: bold;">Sort:</span>
            <button onclick="window.spellSortType = 'alphabetical'; switchCollectionTab('spells');" style="padding: 5px 10px; background: ${window.spellSortType === 'alphabetical' ? '#9b59b6' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">A-Z</button>
            <button onclick="window.spellSortType = 'rarity'; switchCollectionTab('spells');" style="padding: 5px 10px; background: ${window.spellSortType === 'rarity' ? '#9b59b6' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">Rarity</button>
            <button onclick="window.spellSortType = 'cost'; switchCollectionTab('spells');" style="padding: 5px 10px; background: ${window.spellSortType === 'cost' ? '#9b59b6' : '#555'}; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 11px;">Cost</button>
            <div style="border-left: 1px solid #555; height: 20px; margin: 0 3px;"></div>
            <span style="color: #aaa; font-size: 12px; font-weight: bold;">Element:</span>
            <select onchange="window.spellElementFilter = this.value; switchCollectionTab('spells');" style="padding: 5px 8px; background: #444; border: 1px solid #555; border-radius: 6px; color: white; font-size: 11px; cursor: pointer;">
              <option value="all" ${window.spellElementFilter === 'all' ? 'selected' : ''}>All</option>
              <option value="none" ${window.spellElementFilter === 'none' ? 'selected' : ''}>None</option>
              ${elements.map(elem => `<option value="${elem}" ${window.spellElementFilter === elem ? 'selected' : ''} style="color: ${getElementColor(elem)}">${elem}</option>`).join('')}
            </select>
            <span style="color: #666; font-size: 10px; margin-left: auto;">${sortedSpells.length} of ${spellsData.length}</span>
          </div>

          <div id="spells-grid" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); gap: 10px; overflow-y: auto;">
            ${sortedSpells.map(spell => {
              const rarityColor = getRarityColor(spell.rarity);
              const elementColor = getElementColor(spell.element);
              return `
              <div
                class="collection-spell-card"
                data-spell-name="${spell.name.replace(/"/g, '&quot;')}"
                onclick="showSpellDetails('${spell.name.replace(/'/g, "\\'")}')"
                style="
                  background: rgba(0,0,0,0.3);
                  border: 2px solid ${rarityColor};
                  border-radius: 8px;
                  padding: 8px;
                  display: flex;
                  flex-direction: column;
                  align-items: center;
                  gap: 6px;
                  transition: transform 0.2s, box-shadow 0.2s;
                  cursor: pointer;
                "
                onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 6px 15px rgba(0,0,0,0.5)';"
                onmouseout="this.style.transform=''; this.style.boxShadow='';"
              >
                <img
                  src="${spell.image || 'images/spells/no-spell.svg'}"
                  alt="${spell.name}"
                  style="
                    width: 80px;
                    height: 80px;
                    object-fit: contain;
                    border-radius: 6px;
                    background: rgba(0,0,0,0.2);
                    image-rendering: pixelated;
                  "
                  onerror="this.style.opacity='0.3';"
                />
                <div style="text-align: center; font-size: 11px; font-weight: bold; color: ${rarityColor}; word-wrap: break-word; width: 100%;">
                  ${spell.name}
                </div>
                <div style="display: flex; gap: 6px; justify-content: center; align-items: center;">
                  <span style="font-size: 10px; color: #66b3ff; font-weight: bold;">${spell.cost} Mana</span>
                  ${spell.element && spell.element !== 'N/A' ? `<span style="font-size: 9px; color: ${elementColor}; font-weight: bold;">${spell.element}</span>` : ''}
                </div>
                <div style="font-size: 9px; color: ${rarityColor}; text-align: center; text-transform: uppercase; font-weight: bold;">
                  ${spell.rarity}
                </div>
              </div>
            `;
            }).join('')}
          </div>
        </div>

        <!-- Right side: Spell details -->
        <div id="spell-details" style="flex: 1; overflow-y: auto; padding: 20px; background: rgba(0,0,0,0.2); border: 1px solid #444; border-radius: 8px; min-width: 300px;">
          <div style="text-align: center; color: #888; padding: 40px 20px;">
            <p>Click a spell to view details</p>
          </div>
        </div>
      `;
    }
  }
}

// Sort collection spells
function sortCollectionSpells(sortType) {
  window.spellSortType = sortType;
  switchCollectionTab('spells');
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
        <div
          class="collection-item-card"
          data-item-name="${item.name.replace(/"/g, '&quot;')}"
          onclick="showItemDetails('${item.name.replace(/'/g, "\\'")}')"
          style="
            background: rgba(0,0,0,0.3);
            border: 2px solid ${rarityColor};
            border-radius: 8px;
            padding: 8px;
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 6px;
            transition: transform 0.2s, box-shadow 0.2s;
            cursor: pointer;
          "
          onmouseover="this.style.transform='translateY(-3px)'; this.style.boxShadow='0 6px 15px rgba(0,0,0,0.5)';"
          onmouseout="this.style.transform=''; this.style.boxShadow='';"
        >
          <img
            src="${item.image || 'images/items/no-item.svg'}"
            alt="${item.name}"
            style="
              width: 80px;
              height: 80px;
              object-fit: contain;
              border-radius: 6px;
              background: rgba(0,0,0,0.2);
              image-rendering: pixelated;
            "
            onerror="this.style.display='none';"
          />
          <div style="text-align: center; font-size: 11px; font-weight: bold; color: ${rarityColor}; word-wrap: break-word; width: 100%;">
            ${item.name}
          </div>
          <div style="font-size: 9px; color: ${rarityColor}; text-align: center; text-transform: uppercase; font-weight: bold;">
            ${item.rarity}
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
window.sortCollectionSpells = sortCollectionSpells;
