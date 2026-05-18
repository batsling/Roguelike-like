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
