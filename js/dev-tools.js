/**
 * Dev tools panel + settings.
 *
 * Extracted from js/main.js as part of the Phase 3 decomposition. This file
 * owns:
 *   - Persistent settings (Specific Enemies toggle, Dev Tools toggle) and
 *     the settings modal (⚙️ button in the top bar).
 *   - The developer panel's UI population functions: dropdown contents for
 *     games / items / curses / enemies / spaces / locations / events /
 *     status games, plus the active-curses list and the master "enable all
 *     dev buttons" helper.
 *
 * Loaded by index.html before main.js. Functions are re-exported on
 * `window.*` at the bottom so the rest of the codebase can call them
 * through the same defensive-typeof seam it used before the extraction.
 *
 * Phase 5 (ESM): the window.* exports go away in favor of named exports.
 */

// ============================================================
// SETTINGS SYSTEM
// ============================================================

const SETTINGS_KEY = 'roguelikeSettings';

/** Load settings from localStorage, merging with defaults. */
function loadSettings() {
  const defaults = { specificEnemies: false, devToolsEnabled: false };
  try {
    const stored = localStorage.getItem(SETTINGS_KEY);
    return stored ? { ...defaults, ...JSON.parse(stored) } : defaults;
  } catch (e) {
    return defaults;
  }
}

/** Show or hide the developer tools panel based on current settings. */
function applyDevToolsVisibility() {
  const panel = document.getElementById('dev-tools-panel');
  if (!panel) return;
  if (gameSettings.devToolsEnabled) {
    panel.classList.remove('dev-tools-hidden');
  } else {
    panel.classList.add('dev-tools-hidden');
  }
}

/** Persist settings to localStorage. */
function saveSettings(settings) {
  try { localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings)); } catch (e) {}
}

/** Current in-memory settings (read once on load, written on change). */
let gameSettings = loadSettings();
// Apply visibility-driven settings as soon as the DOM is ready
document.addEventListener('DOMContentLoaded', applyDevToolsVisibility);

/** Show the settings modal. */
function showSettingsModal() {
  const overlay = document.createElement('div');
  overlay.id = 'settings-overlay';
  overlay.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,0.75);display:flex;align-items:center;justify-content:center;z-index:30000;';

  overlay.innerHTML = `
    <div style="background:#1a1a2e;border:2px solid #444;border-radius:12px;padding:28px;min-width:340px;max-width:480px;color:#eee;font-family:inherit;">
      <h2 style="margin:0 0 18px;font-size:20px;color:#fff;">⚙️ Settings</h2>

      <div style="margin-bottom:22px;">
        <h3 style="margin:0 0 10px;font-size:14px;color:#aaa;text-transform:uppercase;letter-spacing:.05em;">Combat</h3>

        <label style="display:flex;align-items:flex-start;gap:12px;cursor:pointer;padding:10px;border-radius:8px;border:1px solid #333;background:#111;">
          <input type="checkbox" id="setting-specific-enemies" style="margin-top:3px;width:16px;height:16px;accent-color:#ff9800;flex-shrink:0;"
            ${gameSettings.specificEnemies ? 'checked' : ''}>
          <span>
            <strong style="display:block;margin-bottom:4px;">Specific Enemies</strong>
            <span style="font-size:12px;color:#aaa;">
              When <b>ON</b>: enemies are limited to those from the game you're currently visiting.<br>
              When <b>OFF</b> (default): any enemy whose type matches the game category can appear
              (Action→Strength, Deckbuilding→Charisma, Strategy→Intelligence, Traditional→Dexterity).
            </span>
          </span>
        </label>
      </div>

      <div style="margin-bottom:22px;">
        <h3 style="margin:0 0 10px;font-size:14px;color:#aaa;text-transform:uppercase;letter-spacing:.05em;">Developer</h3>

        <label style="display:flex;align-items:flex-start;gap:12px;cursor:pointer;padding:10px;border-radius:8px;border:1px solid #333;background:#111;">
          <input type="checkbox" id="setting-dev-tools" style="margin-top:3px;width:16px;height:16px;accent-color:#ff9800;flex-shrink:0;"
            ${gameSettings.devToolsEnabled ? 'checked' : ''}>
          <span>
            <strong style="display:block;margin-bottom:4px;">Developer Tools</strong>
            <span style="font-size:12px;color:#aaa;">
              Show the developer panel for spawning enemies, adding items, and triggering encounters directly.
            </span>
          </span>
        </label>
      </div>

      <div style="display:flex;justify-content:flex-end;gap:10px;">
        <button id="settings-save" style="padding:8px 20px;background:#4CAF50;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:14px;">Save</button>
        <button id="settings-cancel" style="padding:8px 20px;background:#555;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:14px;">Cancel</button>
      </div>
    </div>
  `;

  document.body.appendChild(overlay);

  overlay.querySelector('#settings-save').addEventListener('click', () => {
    gameSettings.specificEnemies = overlay.querySelector('#setting-specific-enemies').checked;
    gameSettings.devToolsEnabled = overlay.querySelector('#setting-dev-tools').checked;
    saveSettings(gameSettings);
    applyDevToolsVisibility();
    overlay.remove();
  });

  overlay.querySelector('#settings-cancel').addEventListener('click', () => overlay.remove());
  overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });
}

document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('settings-btn')?.addEventListener('click', showSettingsModal);
});

// ============================================================
// DEV PANEL POPULATION
// ============================================================

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

// ============================================================
// Re-export to window for cross-file access (legacy script-tag model).
// Removed by Phase 5 when callers switch to import statements.
// ============================================================

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

  const removed = inventory[itemIndex];
  StateMutator.removeItem(itemIndex);

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
  const removed = inventory[randomIndex];
  StateMutator.removeItem(randomIndex);

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

if (typeof window !== 'undefined') {
  window.loadSettings = loadSettings;
  window.saveSettings = saveSettings;
  window.applyDevToolsVisibility = applyDevToolsVisibility;
  window.showSettingsModal = showSettingsModal;
  window.populateGameSelects = populateGameSelects;
  window.populateItemSelects = populateItemSelects;
  window.populateCurseSelects = populateCurseSelects;
  window.populateEnemySelect = populateEnemySelect;
  window.populateSpaceSelect = populateSpaceSelect;
  window.populateDifficultyLocationSelect = populateDifficultyLocationSelect;
  window.updateCurrentLocationDisplay = updateCurrentLocationDisplay;
  window.populateStatusGameSelect = populateStatusGameSelect;
  window.populateEventSelect = populateEventSelect;
  window.updateActiveCursesList = updateActiveCursesList;
  window.enableButtons = enableButtons;
}
