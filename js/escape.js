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
  const charCount = typeof CHARACTERS_DATA !== 'undefined' ? Object.keys(CHARACTERS_DATA).length : 0;
  const cardCount = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.filter(c => c.rarity !== 'Starter' && c.type !== 'Status').length : 0;
  const spellCount = typeof SPELLS_DATA !== 'undefined' ? SPELLS_DATA.length : 0;

  const collectionHTML = `
    <style>
      .col-tab-btn { padding: 6px 12px; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold; font-size: 12px; transition: all 0.15s; }
      .col-tab-btn:hover { filter: brightness(1.2); }
      .col-card-hover { transition: transform 0.18s, box-shadow 0.18s; cursor: pointer; }
      .col-card-hover:hover { transform: translateY(-3px); box-shadow: 0 6px 18px rgba(0,0,0,0.6); }
      @keyframes shimmer { 0%,100%{opacity:1} 50%{opacity:0.55} }
      .rarity-shimmer { animation: shimmer 2.4s ease-in-out infinite; }
      .glass-panel { background: rgba(15,15,20,0.65); backdrop-filter: blur(8px); border: 1px solid rgba(255,255,255,0.08); }
    </style>
    <div style="width: 90vw; max-width: 1400px; max-height: 85vh; overflow: hidden; display: flex; flex-direction: column;">
      <div style="display: flex; gap: 6px; padding-bottom: 10px; margin-bottom: 12px; border-bottom: 2px solid #333; align-items: center; flex-wrap: wrap;">
        <h2 style="color: #ff9800; margin: 0; flex: 1; min-width: 110px; font-size: 18px;">📚 Collection</h2>
        <button class="col-tab-btn" onclick="switchCollectionTab('games')" id="tab-games" style="background:#ff9800;">Games (${games.length})</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('characters')" id="tab-characters" style="background:#555;">Characters (${charCount})</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('cards')" id="tab-cards" style="background:#555;">Cards (${cardCount})</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('items')" id="tab-items" style="background:#555;">Items (${items.length})</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('loot')" id="tab-loot" style="background:#555;">Loot</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('enemies')" id="tab-enemies" style="background:#555;">Enemies (${enemies.length})</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('curses')" id="tab-curses" style="background:#555;">Curses (${curses.length})</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('statuses')" id="tab-statuses" style="background:#555;">Reference</button>
        <button class="col-tab-btn" onclick="switchCollectionTab('spells')" id="tab-spells" style="background:#555;">Spells (${spellCount})</button>
        <button class="col-tab-btn" onclick="closeGameModal();" style="background:#333; margin-left: 4px;">✕ Close</button>
      </div>
      <div id="collection-content" style="flex: 1; overflow: hidden; display: flex; gap: 16px;">
      </div>
    </div>
  `;

  createGameModal(collectionHTML);
  switchCollectionTab('games');
}

function switchCollectionTab(tab) {
  // Save focus state before re-rendering
  const activeElement = document.activeElement;
  const activeId = activeElement ? activeElement.id : null;
  const selectionStart = activeElement && activeElement.selectionStart !== undefined ? activeElement.selectionStart : null;
  const selectionEnd = activeElement && activeElement.selectionEnd !== undefined ? activeElement.selectionEnd : null;

  // Update tab buttons
  const tabs = ['games', 'characters', 'cards', 'items', 'loot', 'enemies', 'curses', 'statuses', 'spells'];
  tabs.forEach(t => {
    const btn = document.getElementById(`tab-${t}`);
    if (btn) btn.style.background = t === tab ? '#ff9800' : '#555';
  });

  const content = document.getElementById('collection-content');
  if (!content) return;

  // Helper to restore focus after content update
  const restoreFocus = () => {
    if (activeId) {
      const element = document.getElementById(activeId);
      if (element) {
        element.focus();
        if (selectionStart !== null && element.setSelectionRange) {
          element.setSelectionRange(selectionStart, selectionEnd);
        }
      }
    }
  };

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
    if (typeof window.charactersSearchTerm === 'undefined') window.charactersSearchTerm = '';
    if (!window.characterSortType) window.characterSortType = 'alphabetical';

    const rawChars = typeof CHARACTERS_DATA !== 'undefined' ? Object.values(CHARACTERS_DATA) : [];
    const searchTerm = window.charactersSearchTerm.toLowerCase();
    let filtered = searchTerm
      ? rawChars.filter(c => c.name.toLowerCase().includes(searchTerm) || (c.game || '').toLowerCase().includes(searchTerm))
      : [...rawChars];

    if (window.characterSortType === 'game') {
      filtered.sort((a, b) => (a.game || '').localeCompare(b.game || '') || a.name.localeCompare(b.name));
    } else {
      filtered.sort((a, b) => a.name.localeCompare(b.name));
    }

    content.innerHTML = `
      <div style="flex: 2; overflow-y: auto; padding: 10px; display: flex; flex-direction: column;">
        <div style="display: flex; gap: 8px; margin-bottom: 12px; padding: 8px 12px; background: rgba(0,0,0,0.35); border-radius: 8px; align-items: center; flex-wrap: wrap;">
          <input type="text" placeholder="🔍 Search characters…" value="${window.charactersSearchTerm}"
            oninput="window.charactersSearchTerm = this.value; switchCollectionTab('characters');"
            style="flex:1; min-width:130px; padding:6px 10px; background:rgba(0,0,0,0.4); border:1px solid #444; border-radius:6px; color:white; font-size:12px; outline:none;"/>
          <span style="color:#555; font-size:13px;">|</span>
          <button onclick="window.characterSortType='alphabetical'; switchCollectionTab('characters');" style="padding:5px 10px; background:${window.characterSortType==='alphabetical'?'#4CAF50':'#444'}; border:none; border-radius:5px; color:white; cursor:pointer; font-size:11px; font-weight:bold;">A-Z</button>
          <button onclick="window.characterSortType='game'; switchCollectionTab('characters');" style="padding:5px 10px; background:${window.characterSortType==='game'?'#4CAF50':'#444'}; border:none; border-radius:5px; color:white; cursor:pointer; font-size:11px; font-weight:bold;">Game</button>
          <span style="color:#555; font-size:11px; margin-left:auto;">${filtered.length}/${rawChars.length}</span>
        </div>
        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 12px; overflow-y: auto;">
          ${filtered.map(char => `
            <div class="col-card-hover glass-panel" onclick="showCharacterDetails('${char.name.replace(/'/g,"\\'")}') "
              style="border-radius:10px; padding:14px 10px; display:flex; flex-direction:column; align-items:center; gap:8px;
                     border: 2px solid rgba(76,175,80,0.5); box-shadow: 0 0 10px rgba(76,175,80,0.12);">
              <img src="${char.icon || 'images/characters/Icon/' + char.name + '.png'}" alt="${char.name}"
                style="width:90px; height:90px; object-fit:contain; border-radius:8px; background:rgba(0,0,0,0.3); image-rendering:pixelated;"
                onerror="this.style.opacity='0.25';"/>
              <div style="font-size:12px; font-weight:bold; color:#4CAF50; text-align:center;">${char.name}</div>
              <div style="font-size:10px; color:#888; text-align:center;">${char.game || ''}</div>
              <div style="font-size:10px; color:#aaa;">❤ ${char.health || '?'} &nbsp;⚡ ${char.energy || 0}</div>
            </div>
          `).join('')}
        </div>
      </div>
      <div id="character-details" class="glass-panel" style="flex:1; overflow-y:auto; padding:20px; border-radius:10px; min-width:280px;">
        <div style="text-align:center; color:#666; padding:40px 20px; font-size:13px;">Select a character to view details</div>
      </div>
    `;
  } else if (tab === 'cards') {
    if (typeof window.cardsSearchTerm === 'undefined') window.cardsSearchTerm = '';
    if (typeof window.cardsTypeFilter === 'undefined') window.cardsTypeFilter = 'all';
    if (typeof window.cardsRarityFilter === 'undefined') window.cardsRarityFilter = 'all';
    if (typeof window.cardsSortType === 'undefined') window.cardsSortType = 'rarity';

    const allCards = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA : [];
    // Exclude status cards and starters from main pool view
    let filteredCards = allCards.filter(c => c.type !== 'Status');

    const searchTerm = window.cardsSearchTerm.toLowerCase();
    if (searchTerm) {
      filteredCards = filteredCards.filter(c =>
        c.name.toLowerCase().includes(searchTerm) ||
        (c.description || '').toLowerCase().includes(searchTerm)
      );
    }
    if (window.cardsTypeFilter !== 'all') {
      filteredCards = filteredCards.filter(c => (c.type || '').toLowerCase() === window.cardsTypeFilter);
    }
    if (window.cardsRarityFilter !== 'all') {
      filteredCards = filteredCards.filter(c => (c.rarity || '').toLowerCase() === window.cardsRarityFilter);
    }

    const rarityOrder = { 'legendary':5,'rare':4,'uncommon':3,'common':2,'starter':1 };
    const typeOrder = { 'attack':1,'skill':2,'power':3,'training':4,'dice':5 };
    if (window.cardsSortType === 'rarity') {
      filteredCards.sort((a,b) => (rarityOrder[(b.rarity||'').toLowerCase()]||0) - (rarityOrder[(a.rarity||'').toLowerCase()]||0) || a.name.localeCompare(b.name));
    } else if (window.cardsSortType === 'type') {
      filteredCards.sort((a,b) => (typeOrder[(a.type||'').toLowerCase()]||9) - (typeOrder[(b.type||'').toLowerCase()]||9) || a.name.localeCompare(b.name));
    } else if (window.cardsSortType === 'cost') {
      filteredCards.sort((a,b) => (a.cost||0) - (b.cost||0) || a.name.localeCompare(b.name));
    } else {
      filteredCards.sort((a,b) => a.name.localeCompare(b.name));
    }

    const getRarityColor = (r) => {
      switch((r||'').toLowerCase()) {
        case 'legendary': return '#ff6b00';
        case 'rare': return '#9b59b6';
        case 'uncommon': return '#4CAF50';
        case 'common': return '#aaa';
        case 'starter': return '#2196F3';
        default: return '#666';
      }
    };
    const getTypeColor = (t) => {
      switch((t||'').toLowerCase()) {
        case 'attack': return '#e74c3c';
        case 'skill': return '#2980b9';
        case 'power': return '#8e44ad';
        case 'training': return '#27ae60';
        case 'dice': return '#d35400';
        default: return '#888';
      }
    };

    const cardTypes = [...new Set(allCards.filter(c=>c.type!=='Status').map(c=>c.type).filter(Boolean))].sort();
    const rarities = [...new Set(allCards.filter(c=>c.type!=='Status').map(c=>c.rarity).filter(Boolean))].sort();

    content.innerHTML = `
      <div style="flex:2; overflow-y:auto; padding:10px; display:flex; flex-direction:column;">
        <!-- Controls -->
        <div style="display:flex; gap:6px; margin-bottom:12px; padding:8px 12px; background:rgba(0,0,0,0.35); border-radius:8px; align-items:center; flex-wrap:wrap;">
          <input type="text" placeholder="🔍 Search cards…" value="${window.cardsSearchTerm}"
            oninput="window.cardsSearchTerm=this.value; switchCollectionTab('cards');"
            style="flex:1; min-width:120px; padding:6px 10px; background:rgba(0,0,0,0.4); border:1px solid #444; border-radius:6px; color:white; font-size:12px; outline:none;"/>
          <span style="color:#555;">|</span>
          <select onchange="window.cardsTypeFilter=this.value; switchCollectionTab('cards');" style="padding:5px 8px; background:#333; border:1px solid #444; border-radius:6px; color:white; font-size:11px; cursor:pointer;">
            <option value="all" ${window.cardsTypeFilter==='all'?'selected':''}>All Types</option>
            ${cardTypes.map(t=>`<option value="${t.toLowerCase()}" ${window.cardsTypeFilter===t.toLowerCase()?'selected':''}>${t}</option>`).join('')}
          </select>
          <select onchange="window.cardsRarityFilter=this.value; switchCollectionTab('cards');" style="padding:5px 8px; background:#333; border:1px solid #444; border-radius:6px; color:white; font-size:11px; cursor:pointer;">
            <option value="all" ${window.cardsRarityFilter==='all'?'selected':''}>All Rarities</option>
            ${rarities.map(r=>`<option value="${r.toLowerCase()}" ${window.cardsRarityFilter===r.toLowerCase()?'selected':''}>${r}</option>`).join('')}
          </select>
          <span style="color:#555;">|</span>
          <button onclick="window.cardsSortType='rarity'; switchCollectionTab('cards');" style="padding:5px 9px; background:${window.cardsSortType==='rarity'?'#ff9800':'#444'}; border:none; border-radius:5px; color:white; cursor:pointer; font-size:11px; font-weight:bold;">Rarity</button>
          <button onclick="window.cardsSortType='type'; switchCollectionTab('cards');" style="padding:5px 9px; background:${window.cardsSortType==='type'?'#ff9800':'#444'}; border:none; border-radius:5px; color:white; cursor:pointer; font-size:11px; font-weight:bold;">Type</button>
          <button onclick="window.cardsSortType='cost'; switchCollectionTab('cards');" style="padding:5px 9px; background:${window.cardsSortType==='cost'?'#ff9800':'#444'}; border:none; border-radius:5px; color:white; cursor:pointer; font-size:11px; font-weight:bold;">Cost</button>
          <button onclick="window.cardsSortType='alpha'; switchCollectionTab('cards');" style="padding:5px 9px; background:${window.cardsSortType==='alpha'?'#ff9800':'#444'}; border:none; border-radius:5px; color:white; cursor:pointer; font-size:11px; font-weight:bold;">A-Z</button>
          <span style="color:#555; font-size:11px; margin-left:auto;">${filteredCards.length}/${allCards.filter(c=>c.type!=='Status').length}</span>
        </div>
        <!-- Card grid -->
        <div style="display:grid; grid-template-columns:repeat(auto-fill, minmax(120px, 1fr)); gap:10px; overflow-y:auto;">
          ${filteredCards.map(card => {
            const rc = getRarityColor(card.rarity);
            const tc = getTypeColor(card.type);
            const isShimmer = (card.rarity||'').toLowerCase() === 'rare' || (card.rarity||'').toLowerCase() === 'legendary';
            return `
            <div class="col-card-hover ${isShimmer?'rarity-shimmer':''}" onclick="showCardDetails('${card.name.replace(/'/g,"\\'")}') "
              style="border-radius:10px; border:2px solid ${rc}; background:rgba(10,10,15,0.8);
                     box-shadow: 0 0 8px ${rc}44; display:flex; flex-direction:column; overflow:hidden; min-height:160px; position:relative;">
              <!-- Cost bubble -->
              <div style="position:absolute; top:6px; left:6px; width:22px; height:22px; border-radius:50%;
                           background:${tc}; border:2px solid rgba(255,255,255,0.3); display:flex; align-items:center; justify-content:center;
                           font-size:11px; font-weight:bold; color:white; z-index:2;">
                ${card.cost !== null && card.cost !== undefined ? card.cost : '?'}
              </div>
              <!-- Card image -->
              ${card.imageUrl ? `
                <img src="${card.imageUrl}" alt="${card.name}"
                  style="width:100%; height:80px; object-fit:contain; background:rgba(0,0,0,0.3); image-rendering:pixelated;"
                  onerror="this.style.display='none';"/>
              ` : `<div style="width:100%; height:80px; background:linear-gradient(135deg,${tc}33,${rc}22); display:flex; align-items:center; justify-content:center; font-size:28px; color:${tc}88;">
                ${(card.type||'').toLowerCase()==='attack'?'⚔':(card.type||'').toLowerCase()==='skill'?'🛡':(card.type||'').toLowerCase()==='power'?'✨':'🃏'}
              </div>`}
              <!-- Card info -->
              <div style="padding:6px; flex:1; display:flex; flex-direction:column; gap:3px;">
                <div style="font-size:11px; font-weight:bold; color:#eee; line-height:1.2;">${card.name}</div>
                <div style="font-size:9px; color:${tc}; text-transform:uppercase; font-weight:bold;">${card.type || ''}</div>
                <div style="font-size:9px; color:${rc}; text-transform:uppercase;">${card.rarity || ''}</div>
              </div>
            </div>
          `;}).join('')}
        </div>
      </div>
      <div id="card-details" class="glass-panel" style="flex:1; overflow-y:auto; padding:20px; border-radius:10px; min-width:280px;">
        <div style="text-align:center; color:#666; padding:40px 20px; font-size:13px;">Select a card to view details</div>
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

        <div id="items-grid" style="display: grid; grid-template-columns: repeat(auto-fill, minmax(110px, 1fr)); gap: 10px; overflow-y: auto;">
          ${sortedItems.map(item => {
            const rarityColor = getRarityColor(item.rarity);
            const isShimmer = ['legendary','rare'].includes((item.rarity||'').toLowerCase());
            return `
            <div class="col-card-hover ${isShimmer?'rarity-shimmer':''}"
              onclick="showItemDetails('${item.name.replace(/'/g, "\\'")}')"
              style="background:rgba(10,10,15,0.8); border:2px solid ${rarityColor};
                     box-shadow:0 0 8px ${rarityColor}44; border-radius:10px; padding:10px;
                     display:flex; flex-direction:column; align-items:center; gap:6px;">
              <img src="${item.image || ''}" alt="${item.name}"
                style="width:72px; height:72px; object-fit:contain; border-radius:6px; background:rgba(0,0,0,0.3); image-rendering:pixelated;"
                onerror="this.style.display='none';"/>
              <div style="text-align:center; font-size:11px; font-weight:bold; color:${rarityColor}; word-break:break-word; width:100%;">${item.name}</div>
              <div style="font-size:9px; color:${rarityColor}; text-transform:uppercase; font-weight:bold;">${item.rarity||''}</div>
            </div>
          `;
          }).join('')}
        </div>
      </div>
      <div id="item-details" class="glass-panel" style="flex:1; overflow-y:auto; padding:20px; border-radius:10px; min-width:280px;">
        <div style="text-align:center; color:#666; padding:40px 20px; font-size:13px;">Select an item to view details</div>
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
    // Allies tab removed — redirect to characters
    switchCollectionTab('characters');
    return;
  } else if (tab === '_allies_removed') {
    // Allies tab removed — no-op
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
    // Embedded reference data from design spreadsheet
    const REF_STATUSES = [
      {name:'Burn',desc:'Deals 3 damage to target at the end of turn',type:'Debuff',stackable:true,decay:'Down by 1 at end of turn',who:'All',file:'Burn',rarity:'Common'},
      {name:'Poison',desc:'Deals X damage to any target where X is the stack at the start of turn',type:'Debuff',stackable:true,decay:'Down by 1 at end of turn',who:'All',file:'Poison',rarity:'Common'},
      {name:'Dodge',desc:'Negate the next X sources of damage where X is the stack',type:'Buff',stackable:true,decay:'Down when player was going to lose health',who:'All',file:'Dodge',rarity:'Rare'},
      {name:'Power',desc:'Raise or Lower the damage dealt by this target by X',type:'Buff',stackable:true,decay:'None',who:'All',file:'Power',rarity:'Uncommon'},
      {name:'Defense',desc:'Raise or Lower the Block gained by this target by X',type:'Buff',stackable:true,decay:'None',who:'All',file:'Defense',rarity:'Uncommon'},
      {name:'Oiled',desc:'Burn deals double damage, and at end of turn, Dex save 10 or Lose 1 Energy',type:'Debuff',stackable:true,decay:'Down by 1 at end of turn',who:'All',file:'Oiled',rarity:''},
      {name:'Forgetful',desc:'This enemy cannot repeat any of its intents until it has performed all of them.',type:'Ability',stackable:false,decay:'Down by 1 when all sides have been rolled',who:'Enemy',file:'Forgetful',rarity:''},
      {name:'Barricade',desc:'Block is not removed at the start of each turn',type:'Ability',stackable:false,decay:'None',who:'All',file:'Barricade',rarity:'Rare'},
      {name:'Ruptured',desc:'Deals 3 damage to the player when they use a dash to gain dodge',type:'Debuff',stackable:true,decay:'Down by 1 when dash is used',who:'All',file:'Ruptured',rarity:''},
      {name:'Enfeebled',desc:'All damage deals double to target',type:'Debuff',stackable:true,decay:'Down by 1 at end of turn',who:'All',file:'Enfeebled',rarity:'Rare'},
      {name:'Frail',desc:'Reduces Block gained by 25%',type:'Debuff',stackable:true,decay:'Down by 1 at end of turn',who:'All',file:'Frail',rarity:'Common'},
      {name:'Formless',desc:'When dealt damage, change its intent',type:'Ability',stackable:false,decay:'None',who:'Enemy',file:'Formless',rarity:''},
      {name:'Multi Attack X',desc:'This enemy has X amount of intents in a turn',type:'Ability',stackable:false,decay:'None',who:'Enemy',file:'MultiAttack',rarity:''},
      {name:'Ritual',desc:'At the end of its turn, gains X Power',type:'Buff',stackable:true,decay:'None',who:'All',file:'Ritual',rarity:'Rare'},
      {name:'Confused',desc:'Each Dice Energy Cost is randomized between 0 and your max energy every roll',type:'Debuff',stackable:true,decay:'Down by 1 at end of turn',who:'Player',file:'Confused',rarity:''},
      {name:'Fading X',desc:'Dies in X turns',type:'Debuff',stackable:true,decay:'Down by 1 at end of turn',who:'All',file:'Fading',rarity:''},
      {name:'Shifting',desc:'Loses X Power where X is the amount of damage taken this turn. Gain X Shackled.',type:'Debuff',stackable:false,decay:'None',who:'All',file:'Shifting',rarity:''},
      {name:'Thorns',desc:'When a target with Thorns gets dealt or deals Melee Dmg, the target deals X Dmg to the attacker/recipient',type:'Buff',stackable:true,decay:'None',who:'All',file:'Thorns',rarity:'Uncommon'},
      {name:'Vulnerable',desc:'All damage deals 50% more to target',type:'Debuff',stackable:true,decay:'Down by 1 at end of turn',who:'All',file:'Vulnerable',rarity:'Common'},
      {name:'Weak',desc:'Target deals 25% less damage.',type:'Debuff',stackable:true,decay:'Down by 1 at end of turn',who:'All',file:'Weak',rarity:'Common'},
      {name:'Stun',desc:'The enemy\'s intent will be changed to "Stunned" and will do nothing on this turn',type:'Debuff',stackable:false,decay:'Down by 1 at end of turn',who:'Enemy',file:'Stun',rarity:''},
      {name:'Unknown',desc:'This enemy intends to do something specific',type:'Intent',stackable:false,decay:'None',who:'Enemy',file:'Unknown',rarity:''},
      {name:'Stagger X',desc:'Target will gain Stun when hit with X% of Total Health lost in one hit',type:'Ability',stackable:false,decay:'None',who:'Enemy',file:'Stun',rarity:''},
      {name:'Pigment Rich',desc:'When hit, add a random pigment card to your hand.',type:'Ability',stackable:false,decay:'None',who:'Enemy',file:'PigmentRich',rarity:''},
      {name:'Rerollable',desc:'Attacks from this enemy can be rerolled costing 1 Reroll',type:'Ability',stackable:false,decay:'None',who:'Enemy',file:'Rerollable',rarity:''},
      {name:'Rust',desc:'If this enemy does damage that causes the player to lose health, Downgrade a random passive item',type:'Ability',stackable:false,decay:'None',who:'Enemy',file:'Rust',rarity:''},
      {name:'Brace',desc:'Target takes 1 less damage from all sources per stack. (minimum 1)',type:'Buff',stackable:true,decay:'None',who:'All',file:'Brace',rarity:'Common'},
      {name:'Bruise',desc:'Increases all melee and ranged damage taken by 1 per stack.',type:'Debuff',stackable:true,decay:'None',who:'All',file:'Bruise',rarity:'Common'},
      {name:'Leeches',desc:'Drains 1 health per stack from all afflicted units at the end of the applier\'s turn and gives it to the applier.',type:'Debuff',stackable:true,decay:'None',who:'All',file:'Leeches',rarity:'Uncommon'},
      {name:'Soul Link',desc:'Whenever a soul linked target loses health, all soul linked characters lose that health as well.',type:'Debuff',stackable:false,decay:'None',who:'All',file:'SoulLink',rarity:'Rare'},
      {name:'Holy Shield',desc:'The next time this unit gets hit, take no damage and lose 1 Holy Shield. This takes precedence over Block',type:'Buff',stackable:true,decay:'When the target would take damage',who:'All',file:'HolyShield',rarity:'Rare'},
      {name:'Regeneration',desc:'At the end of target\'s turn, it gains X health where X is the stack',type:'Buff',stackable:true,decay:'Down by 1 at end of turn',who:'All',file:'Regeneration',rarity:'Uncommon'},
      {name:'Curl Up',desc:'Target Gains +X Block upon receiving first attack damage each turn',type:'Ability',stackable:false,decay:'None',who:'All',file:'CurlUp',rarity:''},
      {name:'Split',desc:'When target\'s health is at or below 50%, its intent becomes "Splitting" and it Spawns X enemies with its current HP on its turn',type:'Ability',stackable:false,decay:'None',who:'Enemy',file:'Split',rarity:''},
      {name:'Next Turn Block',desc:'Gain X Block at the start of your next turn',type:'Buff',stackable:true,decay:'Lose all when triggered',who:'Player',file:'NextTurnBlock',rarity:'Common'},
      {name:'Next Turn Draw',desc:'Draw X Cards at the start of your next turn',type:'Buff',stackable:true,decay:'Lose all when triggered',who:'Player',file:'NextTurnDraw',rarity:'Rare'},
      {name:'Next Turn Energy',desc:'Gain X Energy at the start of your next turn',type:'Buff',stackable:true,decay:'Lose all when triggered',who:'Player',file:'NextTurnEnergy',rarity:'Rare'},
      {name:'Shackled',desc:'Regains X Power at the end of target\'s turn, then clears',type:'Buff',stackable:true,decay:'Lose all when triggered',who:'All',file:'Shackled',rarity:''},
      {name:'Blur',desc:'Block is not removed at the start of your next X turns',type:'Buff',stackable:true,decay:'Down by 1 at end of turn',who:'All',file:'Blur',rarity:'Rare'},
      {name:'Choked',desc:'Whenever you play a card this turn, target loses X Health',type:'Debuff',stackable:true,decay:'Lose all at end of turn',who:'Enemy',file:'Choked',rarity:''},
      {name:'Well-Laid Plans',desc:'At the end of your turn, add Retain to up to X Cards',type:'Ability',stackable:true,decay:'None',who:'Player',file:'Well-LaidPlans',rarity:''},
      {name:'No Draw',desc:'You cannot Draw Cards this turn',type:'Debuff',stackable:false,decay:'Down by 1 at end of turn',who:'Player',file:'NoDraw',rarity:''},
      {name:'Burst',desc:'The next X Skills you play are triggered an additional time',type:'Buff',stackable:true,decay:'Lose all at end of turn',who:'Player',file:'Burst',rarity:'Rare'},
      {name:'Corpse Explosion',desc:'On death, this enemy deals X times its Max Health to all other enemies',type:'Debuff',stackable:true,decay:'None',who:'Enemy',file:'CorpseExplosion',rarity:''},
      {name:'Envenom',desc:'Whenever you deal unblocked attack damage, apply X Poison',type:'Ability',stackable:true,decay:'None',who:'Player',file:'Envenom',rarity:''},
      {name:'Double Damage',desc:'Attacks deal double damage for X turns',type:'Buff',stackable:true,decay:'Down by 1 at end of turn',who:'Player',file:'DoubleDamage',rarity:'Rare'},
      {name:'Intangible',desc:'Reduce each instance of damage and health loss to 1',type:'Buff',stackable:true,decay:'Down by 1 at end of turn',who:'All',file:'Intangible',rarity:'Rare'},
      {name:'Evolve',desc:'Whenever you draw a Status card, draw X additional Cards',type:'Ability',stackable:true,decay:'None',who:'Player',file:'Evolve',rarity:''},
      {name:'Combust',desc:'At the end of your turn, lose N Health and deal N×5 damage to all enemies (N = stacks)',type:'Ability',stackable:true,decay:'None',who:'Player',file:'Combust',rarity:''},
      {name:'Dark Embrace',desc:'Whenever a card is Exhausted, draw X cards (X = stacks)',type:'Ability',stackable:true,decay:'None',who:'Player',file:'DarkEmbrace',rarity:''},
      {name:'Feel No Pain',desc:'Whenever a card is Exhausted, gain X Block (X = stacks)',type:'Ability',stackable:true,decay:'None',who:'Player',file:'FeelNoPain',rarity:''},
      {name:'Fire Breathing',desc:'Whenever you draw a Status or Curse card, deal X damage to all enemies (X = stacks)',type:'Ability',stackable:true,decay:'None',who:'Player',file:'FireBreathing',rarity:''},
      {name:'Plated Armor',desc:'At the end of your turn, Gain X Block. Loses 1 stack whenever you take unblocked damage.',type:'Buff',stackable:true,decay:'Down by 1 when receiving unblocked Dmg',who:'All',file:'PlatedArmor',rarity:'Uncommon'},
    ];
    const REF_MOVES = [
      {name:'Dmg',desc:'Deals X damage to target',target:'Enemy',file:'Attack',scaling:'Strength',rarity:'Common'},
      {name:'Block',desc:'Give target X block — X amount of damage a target can take before it affects their health',target:'Ally/Self',file:'Defense',scaling:'Dexterity',rarity:'Common'},
      {name:'Reroll',desc:'Gains X rerolls',target:'Self',file:'Status',scaling:'Charisma',rarity:'Rare'},
      {name:'Heal',desc:'Give target X health',target:'Ally/Self',file:'Health',scaling:'Intelligence',rarity:'Uncommon'},
      {name:'Spawn',desc:'Spawn X Creature — if used by enemies, the new enemy will show "Doing nothing"',target:'Self',file:'Status',scaling:'N/A',rarity:''},
      {name:'Alter',desc:'Alter target into X with the same Health as the original target, but Max Health of X',target:'Self',file:'Status',scaling:'N/A',rarity:''},
      {name:'Get',desc:'Give X status to self',target:'Self',file:'Status',scaling:'Charisma',rarity:'Common'},
      {name:'Inflict',desc:'Inflict X status to target',target:'Enemy',file:'Status',scaling:'Charisma',rarity:'Common'},
      {name:'Cleanse',desc:'Removes X stacks of all debuff statuses',target:'Ally/Self',file:'Status',scaling:'Charisma',rarity:'Uncommon'},
      {name:'Mana',desc:'Gain X Mana',target:'Self',file:'Mana',scaling:'Intelligence',rarity:'Common'},
      {name:'Pain',desc:'Target deals X damage to self (not Melee or Ranged)',target:'Self',file:'Status',scaling:'Strength',rarity:''},
      {name:'Assassinate',desc:'Kill an enemy with at least X health left',target:'Enemy',file:'Assassinate',scaling:'Strength',rarity:'Rare'},
      {name:'Vitality',desc:'Gain X Max Health',target:'Ally/Self',file:'Vitality',scaling:'Intelligence',rarity:'Rare'},
      {name:'Add X to Y',desc:'Target gives X card to your Y (Deck, Hand, or Discard)',target:'Player',file:'Status',scaling:'N/A',rarity:''},
      {name:'Steal X in Y',desc:'Enemy steals X card from the player\'s Y (Deck, Hand, Discard, Any) for the duration of the battle',target:'Player',file:'Status',scaling:'N/A',rarity:''},
      {name:'Consume X in Y for Z',desc:'Steal X from player\'s Y and destroy it permanently, then Get Z status if successful',target:'Player',file:'Status',scaling:'N/A',rarity:''},
      {name:'Lose',desc:'Lose X status Y times (# or All)',target:'Self',file:'Status',scaling:'N/A',rarity:''},
      {name:'Conjure X Y to Z',desc:'Create X number of named Y cards and add them to your Z (Hand, Discard, or Draw)',target:'Self',file:'Status',scaling:'N/A',rarity:''},
    ];
    const REF_ADDONS = [
      {name:'Cantrip',desc:'Whenever this side is rolled, trigger its effect immediately (to a random preferred target)',attachTo:'All',forms:''},
      {name:'Ranged',desc:'Ignores effects that come from contact',attachTo:'Attack, Status',forms:''},
      {name:'Multiply X',desc:'Multiplies this side by X (Example: 2 Damage Multi 2)',attachTo:'All',forms:''},
      {name:'Overload',desc:'Applies this to every target (both player/allies and enemies). ExceptLeft/ExceptRight lets an enemy hit everything except neighbors.',attachTo:'All',forms:'OverloadExceptLeft, OverloadExceptRight'},
      {name:'Cleave',desc:'Applies this to target and every target on its side (Allies or Enemies)',attachTo:'All',forms:''},
      {name:'Engage',desc:'x2 on targets with full health',attachTo:'All',forms:''},
      {name:'Finesse',desc:'This weapon scales damage with Dexterity instead of Strength',attachTo:'Weapon',forms:''},
      {name:'Fishing Weight',desc:'Gain +1 Dmg for every 3 Common, 2 Uncommon, or 1 Rare fish in your loot inventory',attachTo:'Weapon',forms:''},
      {name:'Wealth',desc:'Add +1 for every 10 Gold the player has',attachTo:'All',forms:''},
      {name:'Indiscriminate',desc:'Will use random applicable targets',attachTo:'All',forms:''},
      {name:'Infuse X',desc:'If this kills an enemy, gain X Max Health',attachTo:'All',forms:''},
      {name:'Melee',desc:'Triggers effects from contact (Thorns, etc.)',attachTo:'All',forms:''},
      {name:'Destroy',desc:'Remove this from your deck permanently',attachTo:'All',forms:''},
      {name:'Determined(X-Y)',desc:'Counts as a random number from X to Y, determined before combat begins',attachTo:'All',forms:''},
      {name:'Ethereal',desc:'If this card is in your hand at the end of your turn, it is Exhausted',attachTo:'Cards',forms:''},
      {name:'Innate',desc:'Place this card on the top of your deck at the start of combat',attachTo:'Cards',forms:''},
      {name:'Sly',desc:'This card is Unplayable, but its effect triggers when it is discarded',attachTo:'Cards',forms:''},
      {name:'Unplayable',desc:'This card cannot be played and has no energy cost',attachTo:'Cards',forms:''},
      {name:'Retain',desc:'This card is not discarded at the end of the turn',attachTo:'Cards',forms:''},
    ];

    if (!window.refSubtab) window.refSubtab = 'statuses';
    if (typeof window.refSearch === 'undefined') window.refSearch = '';
    if (!window.refTypeFilter) window.refTypeFilter = 'all';

    const getTypeColor = (type) => {
      switch((type||'').toLowerCase()) {
        case 'buff': return '#4CAF50';
        case 'debuff': return '#f44336';
        case 'ability': return '#9c6bff';
        case 'intent': return '#888';
        default: return '#7ea8be';
      }
    };
    const getRarityColor = (r) => {
      switch((r||'').toLowerCase()) {
        case 'common': return '#aaa';
        case 'uncommon': return '#4CAF50';
        case 'rare': return '#5b9bd5';
        default: return '#555';
      }
    };

    const subBtnStyle = (active) => 'padding:7px 18px;border:none;border-radius:6px 6px 0 0;cursor:pointer;font-weight:bold;font-size:13px;transition:background 0.2s;' +
      (active ? 'background:#ff9800;color:#111;' : 'background:rgba(0,0,0,0.35);color:#aaa;');

    const searchTerm = window.refSearch.toLowerCase();

    let innerHtml = '';

    if (window.refSubtab === 'statuses') {
      let data = REF_STATUSES;
      if (searchTerm) data = data.filter(s => s.name.toLowerCase().includes(searchTerm) || s.desc.toLowerCase().includes(searchTerm));
      if (window.refTypeFilter !== 'all') data = data.filter(s => s.type.toLowerCase() === window.refTypeFilter);

      const typeFilters = ['all','buff','debuff','ability'];
      innerHtml = `
        <div style="display:flex;gap:8px;margin-bottom:12px;flex-wrap:wrap;align-items:center;">
          <span style="color:#aaa;font-size:12px;">Filter:</span>
          ${typeFilters.map(f => '<button onclick="window.refTypeFilter=\'' + f + '\';switchCollectionTab(\'statuses\');" style="padding:5px 12px;border:none;border-radius:5px;cursor:pointer;font-size:11px;font-weight:bold;background:' + (window.refTypeFilter===f ? getTypeColor(f==='all'?'':f) || '#ff9800' : '#444') + ';color:white;">' + (f==='all'?'All':f.charAt(0).toUpperCase()+f.slice(1)) + '</button>').join('')}
          <span style="color:#666;font-size:11px;margin-left:auto;">${data.length} entries</span>
        </div>
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px;overflow-y:auto;">
          ${data.map(s => {
            const tc = getTypeColor(s.type);
            const rc = getRarityColor(s.rarity);
            return '<div style="background:rgba(0,0,0,0.35);border:1px solid ' + tc + '44;border-left:3px solid ' + tc + ';border-radius:8px;padding:12px;display:flex;gap:10px;align-items:flex-start;transition:transform 0.15s,box-shadow 0.15s;" onmouseover="this.style.transform=\'translateY(-2px)\';this.style.boxShadow=\'0 4px 12px rgba(0,0,0,0.5)\';" onmouseout="this.style.transform=\'\';this.style.boxShadow=\'\';"><img src="images/statuses/' + s.file + '.png" alt="' + s.name + '" style="width:44px;height:44px;object-fit:contain;border-radius:5px;background:rgba(0,0,0,0.2);image-rendering:pixelated;flex-shrink:0;" onerror="this.style.opacity=\'0.2\';"/><div style="flex:1;min-width:0;"><div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:5px;gap:6px;"><span style="font-size:13px;font-weight:bold;color:' + tc + ';">' + s.name + '</span><span style="font-size:10px;color:' + tc + ';text-transform:uppercase;font-weight:bold;padding:2px 6px;background:' + tc + '22;border-radius:4px;white-space:nowrap;">' + s.type + '</span></div><div style="font-size:11px;color:#ccc;line-height:1.5;margin-bottom:6px;">' + s.desc + '</div><div style="display:flex;gap:8px;flex-wrap:wrap;font-size:10px;"><span style="color:#888;">Affects: ' + s.who + '</span>' + (s.stackable ? '<span style="color:#66b3ff;">Stackable</span>' : '') + (s.decay && s.decay!=='None' ? '<span style="color:#aaa;" title="' + s.decay + '">Decays</span>' : '') + (s.rarity ? '<span style="color:' + rc + ';margin-left:auto;">' + s.rarity + '</span>' : '') + '</div></div></div>';
          }).join('')}
        </div>
      `;
    } else if (window.refSubtab === 'moves') {
      let data = REF_MOVES;
      if (searchTerm) data = data.filter(m => m.name.toLowerCase().includes(searchTerm) || m.desc.toLowerCase().includes(searchTerm));
      innerHtml = `
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px;overflow-y:auto;">
          ${data.map(m => {
            const rc = getRarityColor(m.rarity);
            return '<div style="background:rgba(0,0,0,0.35);border:1px solid #7ea8be44;border-left:3px solid #7ea8be;border-radius:8px;padding:12px;transition:transform 0.15s,box-shadow 0.15s;" onmouseover="this.style.transform=\'translateY(-2px)\';this.style.boxShadow=\'0 4px 12px rgba(0,0,0,0.5)\';" onmouseout="this.style.transform=\'\';this.style.boxShadow=\'\';"><div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;"><span style="font-size:14px;font-weight:bold;color:#c9d6e3;">' + m.name + '</span>' + (m.rarity ? '<span style="font-size:10px;color:' + rc + ';font-weight:bold;">' + m.rarity + '</span>' : '') + '</div><div style="font-size:11px;color:#ccc;line-height:1.5;margin-bottom:8px;">' + m.desc + '</div><div style="display:flex;gap:10px;flex-wrap:wrap;font-size:10px;color:#888;"><span>Target: <span style="color:#b8d4e8;">' + m.target + '</span></span>' + (m.scaling && m.scaling!=='N/A' ? '<span>Scales: <span style="color:#b8d4e8;">' + m.scaling + '</span></span>' : '') + '</div></div>';
          }).join('')}
        </div>
      `;
    } else if (window.refSubtab === 'addons') {
      let data = REF_ADDONS;
      if (searchTerm) data = data.filter(a => a.name.toLowerCase().includes(searchTerm) || a.desc.toLowerCase().includes(searchTerm));
      innerHtml = `
        <div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px;overflow-y:auto;">
          ${data.map(a => '<div style="background:rgba(0,0,0,0.35);border:1px solid #b8860b44;border-left:3px solid #b8860b;border-radius:8px;padding:12px;transition:transform 0.15s,box-shadow 0.15s;" onmouseover="this.style.transform=\'translateY(-2px)\';this.style.boxShadow=\'0 4px 12px rgba(0,0,0,0.5)\';" onmouseout="this.style.transform=\'\';this.style.boxShadow=\'\';"><div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:6px;"><span style="font-size:14px;font-weight:bold;color:#f0c040;">' + a.name + '</span><span style="font-size:10px;color:#888;">Attaches to: <span style="color:#d4b060;">' + a.attachTo + '</span></span></div><div style="font-size:11px;color:#ccc;line-height:1.5;margin-bottom:6px;">' + a.desc + '</div>' + (a.forms ? '<div style="font-size:10px;color:#888;">Forms: <span style="color:#c8a040;">' + a.forms + '</span></div>' : '') + '</div>').join('')}
        </div>
      `;
    }

    content.innerHTML = `
      <div style="flex:1;overflow-y:auto;padding:10px;display:flex;flex-direction:column;">
        <!-- Subtab buttons -->
        <div style="display:flex;gap:0;margin-bottom:0;border-bottom:2px solid #ff9800;">
          <button onclick="window.refSubtab='statuses';window.refTypeFilter='all';switchCollectionTab('statuses');" style="${subBtnStyle(window.refSubtab==='statuses')}">Statuses</button>
          <button onclick="window.refSubtab='moves';switchCollectionTab('statuses');" style="${subBtnStyle(window.refSubtab==='moves')}">Moves</button>
          <button onclick="window.refSubtab='addons';switchCollectionTab('statuses');" style="${subBtnStyle(window.refSubtab==='addons')}">Addons</button>
        </div>
        <!-- Search bar -->
        <div style="display:flex;gap:10px;margin:12px 0;padding:8px 12px;background:rgba(0,0,0,0.3);border-radius:8px;align-items:center;">
          <span style="color:#aaa;font-size:13px;">&#128269;</span>
          <input type="text" placeholder="Search..." value="${window.refSearch}"
            oninput="window.refSearch=this.value;switchCollectionTab('statuses');"
            style="flex:1;padding:6px 10px;background:rgba(0,0,0,0.3);border:1px solid #555;border-radius:6px;color:white;font-size:13px;outline:none;"
          />
        </div>
        ${innerHtml}
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
                  src="${spell.imageUrl || spell.image || 'images/spells/no-spell.svg'}"
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

  // Restore focus after content update
  restoreFocus();
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
