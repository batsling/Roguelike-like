/**
 * Combat flow orchestration (the post-event runtime that drives a fight
 * and the choices after it).
 *
 * Extracted from js/main.js as part of the Phase 3 decomposition. Owns
 * the high-level orchestration only; the rules engine lives in
 * combat-engine.js and the in-fight UI rendering lives in combat-ui.js.
 *
 * Cluster contents:
 *   - showCombatModal: legacy non-dice combat modal (still used by some
 *     paths; large block of HTML/state wiring for the older flow)
 *   - buildWeightedEncounter: random enemy selection by difficulty + game
 *     genre, called when entering combat from a node
 *   - showDiceCombatModal: new dice-based combat entry point that calls
 *     into combat-engine.initCombat
 *   - handleDiceCombatVictory / handleDiceCombatDefeat: win/lose handlers
 *     (rewards, ally HP sync, save-write, death screen)
 *   - showPostCombatChoiceModal: the Rest / Smith / Shop / Movement-event
 *     picker that fires after a win
 *   - showSmithChoiceModal: up-to-2-free-upgrades picker for the Smith
 *     post-combat option
 *
 * External callers (character-start.js, exploration.js) reach
 * showCombatModal / showDiceCombatModal through defensive typeof checks;
 * the window.* re-exports at the bottom keep that working.
 *
 * Phase 5 (ESM) will replace the window.* exports with named exports.
 */

function showCombatModal() {
  if (enemies.length === 0) return;

  // Set phase to combat
  gameState.phase = 'combat';
  updateInventory(); // Refresh item UI to update usable item buttons

  // Determine stat based on current game type
  const currentGameObj = games.find(g => g.name === gameState.currentGame);
  let requiredStat = 'Strength'; // Default

  if (currentGameObj && currentGameObj.type) {
    const gameType = currentGameObj.type.toLowerCase();
    switch(gameType) {
      case 'action': requiredStat = 'Strength'; break;
      case 'deckbuilding': requiredStat = 'Charisma'; break;
      case 'strategy': requiredStat = 'Intelligence'; break;
      case 'traditional': requiredStat = 'Dexterity'; break;
      default: requiredStat = 'Strength';
    }
  }

  // Difficulty scales with number of games beaten (thresholds match getDifficultyTier)
  const gamesBeaten = gameState.totalGamesBeaten || 0;
  const _thresholds = (typeof DIFFICULTY_THRESHOLDS !== 'undefined') ? DIFFICULTY_THRESHOLDS : { MEDIUM: 4, HARD: 8, INSANE: 12 };
  let powerText = 'Low';
  if (gamesBeaten >= _thresholds.HARD) {
    powerText = 'High';
  } else if (gamesBeaten >= _thresholds.MEDIUM) {
    powerText = 'Medium';
  }

  // Use pre-assigned enemy from node modal if available, otherwise pick randomly
  const _preAssigned = gameState.choiceDetails?.[gameState.currentGame]?.enemies;
  let enemy;
  if (_preAssigned && _preAssigned.length > 0) {
    enemy = _preAssigned[0];
    // Consume the pre-assigned slot so a retry generates fresh enemies
    delete gameState.choiceDetails[gameState.currentGame].enemies;
  } else {
    const matchingEnemies = enemies.filter(e =>
      e.powerLevel === powerText && e.stat === requiredStat
    );
    if (matchingEnemies.length === 0) return;
    enemy = matchingEnemies[Math.floor(Math.random() * matchingEnemies.length)];
  }

  // Initialize combat state
  const combat = window.CombatState.initializeCombat(enemy);

  // Apply any statuses queued by pre-combat events
  if (Array.isArray(gameState.pendingCombatStatuses) && gameState.pendingCombatStatuses.length > 0) {
    for (const pending of gameState.pendingCombatStatuses) {
      if (combat && combat.playerStatuses) {
        combat.playerStatuses[pending.status] = (combat.playerStatuses[pending.status] || 0) + (pending.stacks || 1);
      }
    }
    gameState.pendingCombatStatuses = [];
  }

  const enemyImagePath = getEnemyImagePath(enemy.name);
  const playerImagePath = getPlayerImagePath();

  // Create STS-style combat UI
  const combatHTML = `
    <div id="combat-container" style="
      display: flex;
      flex-direction: column;
      width: 92vw;
      max-width: 1400px;
      height: 90vh;
      max-height: 900px;
      padding: 20px;
      background: linear-gradient(135deg, #1a1410 0%, #2a1810 100%);
      border-radius: 12px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.6);
      position: relative;
      overflow: hidden;
    ">
      <!-- Stats Panel (Hidden by default, slides in from left) -->
      <div id="stats-panel" style="
        position: absolute;
        left: 0;
        top: 0;
        width: 320px;
        height: 100%;
        background: linear-gradient(145deg, rgba(30,30,40,0.98), rgba(20,20,30,0.98));
        border-right: 3px solid #4CAF50;
        border-radius: 12px 0 0 12px;
        padding: 25px;
        transform: translateX(-100%);
        transition: transform 0.3s ease;
        z-index: 1000;
        box-shadow: 4px 0 20px rgba(0,0,0,0.5);
        overflow-y: auto;
      ">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 2px solid rgba(76,175,80,0.3); padding-bottom: 15px;">
          <h3 style="margin: 0; color: #4CAF50; font-size: 24px;">📊 All Stats</h3>
          <button id="close-stats-btn" style="
            background: rgba(255,68,68,0.2);
            border: 2px solid #ff4444;
            border-radius: 6px;
            padding: 6px 12px;
            color: #ff6666;
            cursor: pointer;
            font-size: 18px;
            font-weight: bold;
          ">✕</button>
        </div>
        <div id="all-stats-content" style="display: flex; flex-direction: column; gap: 15px;">
          <!-- Will be populated with all stats -->
        </div>
      </div>

      <!-- Main Combat Area -->
      <div style="
        display: flex;
        flex-direction: column;
        flex: 1;
        min-height: 0;
        gap: 15px;
        overflow-y: auto;
      ">
        <!-- Combat Scene (Player vs Enemy + Dice) -->
        <div style="
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 15px;
        ">
          <!-- Combatants Area -->
          <div style="
            display: flex;
            flex-direction: column;
            gap: 15px;
            flex: 1;
            background: rgba(0,0,0,0.3);
            border: 2px solid #444;
            border-radius: 12px;
            padding: 25px;
          ">
            <!-- Player and Enemy Container -->
            <div style="
              display: flex;
              justify-content: space-between;
              align-items: center;
              gap: 30px;
              flex: 1;
            ">
            <!-- Player (Left) -->
            <div id="player-section" style="
              flex: 1;
              display: flex;
              flex-direction: column;
              align-items: center;
              position: relative;
            ">
              <!-- View All Stats Button -->
              <button id="view-stats-btn" style="
                position: absolute;
                top: -10px;
                left: 10px;
                background: rgba(76,175,80,0.2);
                border: 2px solid #4CAF50;
                border-radius: 6px;
                padding: 6px 12px;
                color: #4CAF50;
                cursor: pointer;
                font-size: 12px;
                font-weight: bold;
                text-transform: uppercase;
                transition: all 0.2s;
              ">📊 Stats</button>

              <div style="text-align: center; margin-bottom: 10px;">
                <p style="margin: 0 0 5px 0; font-size: 14px; color: #4CAF50; font-weight: bold; text-transform: uppercase;">YOU</p>
              </div>

              <!-- Player Image -->
              <div style="
                width: 200px;
                height: 200px;
                margin-bottom: 12px;
                border-radius: 8px;
                background: rgba(0,0,0,0.3);
                padding: 8px;
                border: 2px solid rgba(76,175,80,0.4);
                display: flex;
                align-items: center;
                justify-content: center;
              ">
                <img src="${playerImagePath}" style="
                  width: 100%;
                  height: 100%;
                  image-rendering: pixelated;
                  object-fit: contain;
                " alt="Player">
              </div>

              <!-- Health and Block Bar -->
              <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 12px;">
                <!-- Block Display -->
                <div id="player-block-display" style="
                  position: relative;
                  width: 50px;
                  height: 50px;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  display: none;
                ">
                  <!-- Shield Icon -->
                  <div style="
                    position: absolute;
                    width: 100%;
                    height: 100%;
                    font-size: 50px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    color: #66ccff;
                    text-shadow: 0 0 8px rgba(102,204,255,0.5);
                  ">🛡️</div>
                  <!-- Block Value -->
                  <div id="player-block-value" style="
                    position: relative;
                    z-index: 1;
                    font-size: 18px;
                    font-weight: bold;
                    color: white;
                    text-shadow:
                      -1px -1px 0 #000,
                      1px -1px 0 #000,
                      -1px 1px 0 #000,
                      1px 1px 0 #000,
                      0 0 4px #000;
                  ">0</div>
                </div>

                <!-- HP Bar -->
                <div style="background: #2a2a2a; border-radius: 6px; height: 26px; width: 200px; position: relative; overflow: hidden; border: 2px solid #4CAF50;">
                  <div id="player-hp-bar" style="
                    background: linear-gradient(90deg, #4CAF50, #2E7D32);
                    height: 100%;
                    width: ${(health / maxHealth) * 100}%;
                    transition: width 0.3s ease;
                  "></div>
                  <span id="player-hp" style="
                    position: absolute;
                    top: 50%;
                    left: 50%;
                    transform: translate(-50%, -50%);
                    font-size: 14px;
                    font-weight: bold;
                    text-shadow: 0 0 4px black;
                    color: white;
                  ">${health}/${maxHealth}</span>
                </div>
              </div>

              <!-- Player Effects -->
              <div id="player-effects" style="font-size: 12px; text-align: center; min-height: 20px;">
                <!-- Effects will appear here -->
              </div>
            </div>

            <!-- Enemy Intent Display -->
            <div style="
              display: flex;
              flex-direction: column;
              align-items: center;
              gap: 8px;
              padding: 10px;
            ">
              <div style="
                font-size: 14px;
                font-weight: bold;
                color: #ffaa44;
                text-transform: uppercase;
                letter-spacing: 1px;
                margin-bottom: 5px;
              ">ENEMY INTENT</div>

              <!-- Enemy Dice Container -->
              <div style="
                background: rgba(204,51,51,0.1);
                border: 2px solid #cc3333;
                border-radius: 8px;
                padding: 8px;
              ">
                <div id="enemy-intent-dice-container" style="
                  width: 120px;
                  height: 120px;
                  position: relative;
                "></div>
              </div>

              <!-- Enemy Intent Text -->
              <div id="enemy-intent-text" style="
                background: rgba(0,0,0,0.5);
                padding: 8px 16px;
                border-radius: 6px;
                font-size: 14px;
                font-weight: bold;
                color: #ffaa44;
                text-align: center;
                min-width: 150px;
              ">
                Rolling...
              </div>
            </div>

            <!-- Enemy (Right) -->
            <div id="enemy-section" style="
              flex: 1;
              display: flex;
              flex-direction: column;
              align-items: center;
              position: relative;
            ">
              <div style="text-align: center; margin-bottom: 10px;">
                <h3 style="margin: 0 0 2px 0; color: #ff6644; font-size: 22px; text-shadow: 1px 1px 2px rgba(0,0,0,0.5);">${enemy.name}</h3>
                <p style="margin: 0 0 8px 0; font-size: 12px; color: #999; font-style: italic;">${enemy.game}</p>
              </div>

              <!-- Enemy Image -->
              <div style="
                width: 200px;
                height: 200px;
                margin-bottom: 12px;
                border-radius: 8px;
                background: rgba(0,0,0,0.3);
                padding: 8px;
                border: 2px solid rgba(255,68,68,0.4);
                display: flex;
                align-items: center;
                justify-content: center;
              ">
                <img src="${enemyImagePath}" style="
                  width: 100%;
                  height: 100%;
                  image-rendering: pixelated;
                  object-fit: contain;
                " alt="${enemy.name}" onerror="this.style.display='none'">
              </div>

              <!-- Health and Block Bar -->
              <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 12px;">
                <!-- Block Display -->
                <div id="enemy-block-display" style="
                  position: relative;
                  width: 50px;
                  height: 50px;
                  display: flex;
                  align-items: center;
                  justify-content: center;
                  display: none;
                ">
                  <!-- Shield Icon -->
                  <div style="
                    position: absolute;
                    width: 100%;
                    height: 100%;
                    font-size: 50px;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    color: #66ccff;
                    text-shadow: 0 0 8px rgba(102,204,255,0.5);
                  ">🛡️</div>
                  <!-- Block Value -->
                  <div id="enemy-block-value" style="
                    position: relative;
                    z-index: 1;
                    font-size: 18px;
                    font-weight: bold;
                    color: white;
                    text-shadow:
                      -1px -1px 0 #000,
                      1px -1px 0 #000,
                      -1px 1px 0 #000,
                      1px 1px 0 #000,
                      0 0 4px #000;
                  ">0</div>
                </div>

                <!-- HP Bar -->
                <div style="background: #2a2a2a; border-radius: 6px; height: 26px; width: 200px; position: relative; overflow: hidden; border: 2px solid #ff4444;">
                  <div id="enemy-hp-bar" style="
                    background: linear-gradient(90deg, #ff4444, #cc0000);
                    height: 100%;
                    width: 100%;
                    transition: width 0.3s ease;
                  "></div>
                  <span id="enemy-hp-text" style="
                    position: absolute;
                    top: 50%;
                    left: 50%;
                    transform: translate(-50%, -50%);
                    font-size: 14px;
                    font-weight: bold;
                    text-shadow: 0 0 4px black;
                    color: white;
                  ">${enemy.health}/${enemy.health}</span>
                </div>
              </div>

              <!-- Enemy Stats -->
              <div style="
                background: rgba(0,0,0,0.4);
                border: 1px solid #ff4444;
                border-radius: 6px;
                padding: 8px 16px;
                margin-bottom: 8px;
              ">
                <div style="display: flex; gap: 15px; font-size: 13px; justify-content: center;">
                  <div style="text-align: center;">
                    <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">AC</p>
                    <p style="margin: 2px 0 0 0; color: #66ccff; font-weight: bold; font-size: 16px;">${enemy.armorClass}</p>
                  </div>
                </div>
              </div>

              <!-- Enemy Effects -->
              <div id="enemy-effects" style="font-size: 12px; text-align: center; min-height: 20px;">
                <!-- Effects will appear here -->
              </div>

              <!-- View Combat Log Button -->
              <button id="view-log-btn" style="
                position: absolute;
                top: -10px;
                right: 10px;
                background: rgba(255,204,102,0.2);
                border: 2px solid #ffcc66;
                border-radius: 6px;
                padding: 6px 12px;
                color: #ffcc66;
                cursor: pointer;
                font-size: 12px;
                font-weight: bold;
                text-transform: uppercase;
                transition: all 0.2s;
              ">📜 Log</button>
            </div>
            </div>
          </div>

          <!-- Dice Area (Bottom) -->
          <div id="dice-area" style="
            background: linear-gradient(145deg, rgba(204,102,0,0.15), rgba(204,102,0,0.05));
            border: 3px solid #cc6600;
            border-radius: 12px;
            padding: 15px;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            box-shadow: inset 0 2px 8px rgba(0,0,0,0.3);
            position: relative;
          ">
            <!-- Obstruction Indicator (shown when Curse of Obstruction is active) -->
            <div id="obstruction-indicator" style="
              position: absolute;
              top: 10px;
              left: 50%;
              transform: translateX(-50%);
              background: rgba(255,100,100,0.9);
              border: 2px solid #ff4444;
              border-radius: 8px;
              padding: 8px 16px;
              color: white;
              font-weight: bold;
              font-size: 13px;
              text-align: center;
              display: none;
              box-shadow: 0 4px 12px rgba(255,0,0,0.4);
              z-index: 100;
            ">
              ⚠️ DISADVANTAGE: Roll twice, take lower!
            </div>

            <!-- Energy Display -->
            <div id="energy-display" style="
              position: absolute;
              top: 15px;
              left: 20px;
              display: flex;
              align-items: center;
              gap: 8px;
              background: rgba(255,204,0,0.15);
              border: 2px solid #ffcc00;
              border-radius: 8px;
              padding: 8px 16px;
              box-shadow: 0 2px 8px rgba(255,204,0,0.3);
            ">
              <div style="
                font-size: 18px;
                font-weight: bold;
                color: #ffcc00;
                text-transform: uppercase;
                letter-spacing: 1px;
              ">Energy:</div>
              <div id="energy-bolts" style="
                display: flex;
                gap: 4px;
                font-size: 24px;
              ">⚡⚡</div>
              <div id="energy-count" style="
                font-size: 18px;
                font-weight: bold;
                color: #ffcc00;
              ">2/2</div>
            </div>

            <!-- Dual Dice Container -->
            <div style="
              display: flex;
              gap: 30px;
              align-items: center;
              justify-content: center;
              width: 100%;
              margin-top: 20px;
            ">
              <!-- Attack D20 -->
              <div style="
                display: flex;
                flex-direction: column;
                align-items: center;
                flex: 1;
                max-width: 400px;
              ">
                <div style="
                  display: flex;
                  align-items: center;
                  gap: 8px;
                  margin-bottom: 10px;
                ">
                  <div style="
                    font-size: 14px;
                    font-weight: bold;
                    color: #cc6600;
                    letter-spacing: 0.5px;
                  ">⚔️ Attack for ${attack} damage</div>
                  <div style="
                    font-size: 12px;
                    color: #ffcc00;
                    background: rgba(255,204,0,0.2);
                    border: 1px solid #ffcc00;
                    border-radius: 4px;
                    padding: 2px 6px;
                  ">1⚡</div>
                </div>
                <div style="
                  background: rgba(204,102,0,0.1);
                  border: 2px solid #cc6600;
                  border-radius: 8px;
                  padding: 10px;
                  width: 100%;
                ">
                  <div id="attack-dice-container" class="dice-clickable" style="
                    width: 100%;
                    height: 150px;
                    cursor: pointer;
                    position: relative;
                  "></div>
                  <div id="attack-roll-result" style="
                    margin-top: 6px;
                    font-size: 14px;
                    text-align: center;
                    width: 100%;
                    min-height: 20px;
                  "></div>

                  <!-- Attack Confirm/Reroll Buttons -->
                  <div style="display: flex; flex-direction: column; gap: 8px; margin-top: 10px;">
                    <button id="attack-confirm-btn" disabled style="
                      padding: 8px 20px;
                      font-size: 14px;
                      background: linear-gradient(145deg, #555, #444);
                      border: 2px solid #666;
                      border-radius: 6px;
                      color: #888;
                      cursor: not-allowed;
                      font-weight: bold;
                      opacity: 0.5;
                      text-transform: uppercase;
                      letter-spacing: 0.5px;
                    ">✓ Confirm</button>
                    <button id="attack-reroll-btn" disabled style="
                      padding: 6px 16px;
                      font-size: 12px;
                      background: linear-gradient(145deg, #555, #444);
                      border: 2px solid #666;
                      border-radius: 6px;
                      color: #888;
                      cursor: not-allowed;
                      font-weight: bold;
                      opacity: 0.5;
                      text-transform: uppercase;
                      letter-spacing: 0.5px;
                    ">🔄 Reroll (0)</button>
                  </div>
                </div>
              </div>

              <!-- Defense D6 -->
              <div style="
                display: flex;
                flex-direction: column;
                align-items: center;
                flex: 1;
                max-width: 400px;
              ">
                <div style="
                  display: flex;
                  align-items: center;
                  gap: 8px;
                  margin-bottom: 10px;
                ">
                  <div style="
                    font-size: 14px;
                    font-weight: bold;
                    color: #66ccff;
                    letter-spacing: 0.5px;
                  ">🛡️ Block Roll</div>
                  <div style="
                    font-size: 12px;
                    color: #ffcc00;
                    background: rgba(255,204,0,0.2);
                    border: 1px solid #ffcc00;
                    border-radius: 4px;
                    padding: 2px 6px;
                  ">1⚡</div>
                </div>
                <div style="
                  background: rgba(102,204,255,0.1);
                  border: 2px solid #66ccff;
                  border-radius: 8px;
                  padding: 10px;
                  width: 100%;
                ">
                  <div id="defense-dice-container" class="dice-clickable" style="
                    width: 100%;
                    height: 150px;
                    cursor: pointer;
                    position: relative;
                  "></div>
                  <div id="defense-roll-result" style="
                    margin-top: 6px;
                    font-size: 14px;
                    text-align: center;
                    width: 100%;
                    min-height: 20px;
                  "></div>

                  <!-- Defense Confirm/Reroll Buttons -->
                  <div style="display: flex; flex-direction: column; gap: 8px; margin-top: 10px;">
                    <button id="defense-confirm-btn" disabled style="
                      padding: 8px 20px;
                      font-size: 14px;
                      background: linear-gradient(145deg, #555, #444);
                      border: 2px solid #666;
                      border-radius: 6px;
                      color: #888;
                      cursor: not-allowed;
                      font-weight: bold;
                      opacity: 0.5;
                      text-transform: uppercase;
                      letter-spacing: 0.5px;
                    ">✓ Confirm</button>
                    <button id="defense-reroll-btn" disabled style="
                      padding: 6px 16px;
                      font-size: 12px;
                      background: linear-gradient(145deg, #555, #444);
                      border: 2px solid #666;
                      border-radius: 6px;
                      color: #888;
                      cursor: not-allowed;
                      font-weight: bold;
                      opacity: 0.5;
                      text-transform: uppercase;
                      letter-spacing: 0.5px;
                    ">🔄 Reroll (0)</button>
                  </div>
                </div>
              </div>
            </div>

            <!-- End Turn Button -->
            <button id="end-turn-btn" disabled style="
              position: absolute;
              top: 10px;
              right: 10px;
              padding: 10px 30px;
              font-size: 16px;
              background: linear-gradient(145deg, #555, #444);
              border: 3px solid #666;
              border-radius: 8px;
              color: #888;
              cursor: not-allowed;
              font-weight: bold;
              opacity: 0.5;
              text-transform: uppercase;
              letter-spacing: 1px;
              box-shadow: 0 4px 12px rgba(0,0,0,0.4);
              transition: all 0.3s ease;
            ">⏭️ End Turn</button>
          </div>
        </div>

      </div>

      <!-- Combat Log Panel (Hidden by default, slides in from right) -->
      <div id="log-panel" style="
        position: absolute;
        right: 0;
        top: 0;
        width: 380px;
        height: 100%;
        background: linear-gradient(145deg, rgba(30,30,40,0.98), rgba(20,20,30,0.98));
        border-left: 3px solid #ffcc66;
        border-radius: 0 12px 12px 0;
        padding: 25px;
        transform: translateX(100%);
        transition: transform 0.3s ease;
        z-index: 1000;
        box-shadow: -4px 0 20px rgba(0,0,0,0.5);
        overflow-y: auto;
      ">
        <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; border-bottom: 2px solid rgba(255,204,102,0.3); padding-bottom: 15px;">
          <h3 style="margin: 0; color: #ffcc66; font-size: 24px;">📜 Combat Log</h3>
          <button id="close-log-btn" style="
            background: rgba(255,68,68,0.2);
            border: 2px solid #ff4444;
            border-radius: 6px;
            padding: 6px 12px;
            color: #ff6666;
            cursor: pointer;
            font-size: 18px;
            font-weight: bold;
          ">✕</button>
        </div>
        <div id="combat-log-messages" style="display: flex; flex-direction: column; gap: 8px;">
          <p style="color: #aaa; margin: 0;">⚔️ Combat started! Turn <span style="color: #ffcc66;">1</span></p>
        </div>
      </div>
    </div>
  `;

  createGameModal(combatHTML);

  // Create tooltip element and append to document.body (not inside modal to avoid overflow issues)
  const existingTooltip = document.getElementById('combat-item-tooltip');
  if (existingTooltip) existingTooltip.remove();

  const tooltip = document.createElement('div');
  tooltip.id = 'combat-item-tooltip';
  tooltip.style.cssText = `
    position: fixed;
    display: none;
    background: linear-gradient(145deg, rgba(30,30,40,0.98), rgba(20,20,30,0.98));
    border: 3px solid #888;
    border-radius: 8px;
    padding: 12px 15px;
    max-width: 300px;
    z-index: 9000;
    pointer-events: none;
    box-shadow: 0 4px 20px rgba(0,0,0,0.8);
  `;

  const tooltipContent = document.createElement('div');
  tooltipContent.id = 'combat-tooltip-content';
  tooltip.appendChild(tooltipContent);
  document.body.appendChild(tooltip);

  // Add hover effects CSS for items
  const style = document.createElement('style');
  style.textContent = `
    .item-icon {
      transform: scale(1);
    }
    .item-icon:hover {
      transform: scale(1.15);
      filter: brightness(1.3);
      box-shadow: 0 0 15px rgba(255, 204, 102, 0.6);
      z-index: 10;
    }
    .item-icon:active {
      transform: scale(1.05);
    }
  `;
  document.head.appendChild(style);

  // Initialize 3D dice renderers (separate instances for attack, defense, and enemy)
  const attackDiceContainer = document.getElementById('attack-dice-container');
  const defenseDiceContainer = document.getElementById('defense-dice-container');
  const enemyIntentDiceContainer = document.getElementById('enemy-intent-dice-container');

  const attackRenderer = new window.DiceRendererInstance();
  attackRenderer.init(attackDiceContainer);
  attackRenderer.createDice(combat.dice.attack);

  const defenseRenderer = new window.DiceRendererInstance();
  defenseRenderer.init(defenseDiceContainer);
  defenseRenderer.createDice(combat.dice.defense);

  const enemyIntentRenderer = new window.DiceRendererInstance();
  enemyIntentRenderer.init(enemyIntentDiceContainer);
  enemyIntentRenderer.createDice(combat.dice.enemy);

  // Roll enemy dice and show intent
  showEnemyIntent();

  // Populate items bar
  populateItemsBar();

  // Check for Curse of Obstruction and show indicator
  const obstructionCurses = gameState.activeCurses ? gameState.activeCurses.filter(curse =>
    curse.name && curse.name.toLowerCase().includes('obstruction')
  ) : [];
  const obstructionIndicator = document.getElementById('obstruction-indicator');
  if (obstructionCurses.length > 0 && obstructionIndicator) {
    obstructionIndicator.style.display = 'block';
  }

  // Setup stats panel toggle
  setupStatsPanel();

  // Setup combat log panel toggle
  setupLogPanel();

  // Setup item tooltips
  setupItemTooltips();

  // Update energy display
  updateEnergyDisplay();

  // Pending roll state - stores roll data before confirmation
  const pendingRolls = {
    attack: null,
    defense: null
  };

  // Initialize reroll button text with current reroll count
  updateRerollButtonText();

  // Setup dice click handlers for both attack and defense
  attackDiceContainer.addEventListener('click', () => handleDiceClick('attack'));
  defenseDiceContainer.addEventListener('click', () => handleDiceClick('defense'));

  // Setup confirm button handlers
  document.getElementById('attack-confirm-btn').addEventListener('click', () => handleConfirm('attack'));
  document.getElementById('defense-confirm-btn').addEventListener('click', () => handleConfirm('defense'));

  // Setup reroll button handlers
  document.getElementById('attack-reroll-btn').addEventListener('click', () => handleReroll('attack'));
  document.getElementById('defense-reroll-btn').addEventListener('click', () => handleReroll('defense'));

  // Show enemy intent by rolling their dice
  function showEnemyIntent() {
    const currentCombat = window.CombatState.getCombatState();
    if (!currentCombat || !currentCombat.enemy.plannedAction) return;

    const plannedAction = currentCombat.enemy.plannedAction;
    const intentTextEl = document.getElementById('enemy-intent-text');

    // Animate the enemy dice
    enemyIntentRenderer.rollDice(currentCombat.dice.enemy, plannedAction.sideIndex, (result) => {
      // Update the intent text based on action type
      if (plannedAction.type === 'attack') {
        const totalDamage = plannedAction.value + currentCombat.enemy.strength;
        intentTextEl.innerHTML = `<span style="color: #ff6666;">⚔️ The enemy will attack for ${totalDamage} damage</span>`;
      } else {
        const totalBlock = plannedAction.value + currentCombat.enemy.defence;
        intentTextEl.innerHTML = `<span style="color: #66ccff;">🛡️ The enemy will gain ${totalBlock} block</span>`;
      }
    });
  }

  // Update energy display
  function updateEnergyDisplay() {
    const combat = window.CombatState.getCombatState();
    if (!combat) return;

    const energyBolts = document.getElementById('energy-bolts');
    const energyCount = document.getElementById('energy-count');

    if (energyBolts && energyCount) {
      // Show lightning bolts based on current energy
      const bolts = '⚡'.repeat(combat.player.energy);
      const greyBolts = '<span style="opacity: 0.3;">⚡</span>'.repeat(combat.player.maxEnergy - combat.player.energy);
      energyBolts.innerHTML = bolts + greyBolts;
      energyCount.textContent = `${combat.player.energy}/${combat.player.maxEnergy}`;
    }

    // Update dice container opacity based on available energy
    const attackContainer = document.getElementById('attack-dice-container');
    const defenseContainer = document.getElementById('defense-dice-container');

    if (combat.player.energy < 1) {
      if (attackContainer) attackContainer.style.opacity = '0.4';
      if (defenseContainer) defenseContainer.style.opacity = '0.4';
    } else {
      if (attackContainer) attackContainer.style.opacity = '1';
      if (defenseContainer) defenseContainer.style.opacity = '1';
    }
  }

  // Helper to update reroll button text with current count
  function updateRerollButtonText() {
    const attackRerollBtn = document.getElementById('attack-reroll-btn');
    const defenseRerollBtn = document.getElementById('defense-reroll-btn');
    const rerollCount = gameState.reroll || 0;

    if (attackRerollBtn) {
      attackRerollBtn.textContent = `🔄 Reroll (${rerollCount})`;
    }
    if (defenseRerollBtn) {
      defenseRerollBtn.textContent = `🔄 Reroll (${rerollCount})`;
    }
  }

  // Helper to enable/disable buttons
  function updateButtonStates(diceType, hasRoll, isConfirmed) {
    const confirmBtn = document.getElementById(`${diceType}-confirm-btn`);
    const rerollBtn = document.getElementById(`${diceType}-reroll-btn`);
    const rerollCount = gameState.reroll || 0;

    // Confirm button: enabled after roll, disabled after confirming or no roll
    if (confirmBtn) {
      if (hasRoll && !isConfirmed) {
        confirmBtn.disabled = false;
        confirmBtn.style.opacity = '1';
        confirmBtn.style.cursor = 'pointer';
        confirmBtn.style.background = 'linear-gradient(145deg, #4CAF50, #2E7D32)';
        confirmBtn.style.color = 'white';
        confirmBtn.style.borderColor = '#2E7D32';
      } else {
        confirmBtn.disabled = true;
        confirmBtn.style.opacity = '0.5';
        confirmBtn.style.cursor = 'not-allowed';
        confirmBtn.style.background = 'linear-gradient(145deg, #555, #444)';
        confirmBtn.style.color = '#888';
        confirmBtn.style.borderColor = '#666';
      }
    }

    // Reroll button: enabled after roll if reroll>0, disabled if reroll=0 or confirmed or no roll
    if (rerollBtn) {
      if (hasRoll && !isConfirmed && rerollCount > 0) {
        rerollBtn.disabled = false;
        rerollBtn.style.opacity = '1';
        rerollBtn.style.cursor = 'pointer';
        rerollBtn.style.background = 'linear-gradient(145deg, #9b59b6, #7d3c98)';
        rerollBtn.style.color = 'white';
        rerollBtn.style.borderColor = '#7d3c98';
      } else {
        rerollBtn.disabled = true;
        rerollBtn.style.opacity = '0.5';
        rerollBtn.style.cursor = 'not-allowed';
        rerollBtn.style.background = 'linear-gradient(145deg, #555, #444)';
        rerollBtn.style.color = '#888';
        rerollBtn.style.borderColor = '#666';
      }
    }
  }

  function handleDiceClick(diceType) {
    if (combat.phase !== 'player_turn') {
      return;
    }

    // Don't allow new rolls if this dice already has a pending roll
    if (pendingRolls[diceType]) {
      addCombatLogMessage('Please confirm or reroll the current roll first!', 'warning');
      return;
    }

    const currentCombat = window.CombatState.getCombatState();
    if (!currentCombat || currentCombat.player.energy < 1) {
      addCombatLogMessage('Not enough energy!', 'warning');
      return;
    }

    try {
      // Roll the dice through combat state
      const rollResult = window.CombatState.rollCombatDice(diceType);

      if (!rollResult.success) {
        addCombatLogMessage(rollResult.error, 'danger');
        return;
      }

      // Update energy display
      updateEnergyDisplay();

      // Get the appropriate renderer and result display
      const renderer = diceType === 'attack' ? attackRenderer : defenseRenderer;
      const resultDisplay = document.getElementById(`${diceType}-roll-result`);

      // Get the face number to show on the dice
      // For D20: use the rolled value (1-20)
      // For D6: use sideIndex + 1 to show correct face (1-6)
      const faceNumber = diceType === 'attack'
        ? rollResult.result.baseValue
        : rollResult.result.sideIndex + 1;

      // Animate the 3D dice
      renderer.rollDice(combat.dice[diceType], faceNumber, (result) => {
        if (diceType === 'attack') {
          // Hide obstruction indicator if curse expired
          const obstructionCursesAfterRoll = gameState.activeCurses ? gameState.activeCurses.filter(curse =>
            curse.name && curse.name.toLowerCase().includes('obstruction')
          ) : [];
          const obstructionIndicatorElement = document.getElementById('obstruction-indicator');
          if (obstructionCursesAfterRoll.length === 0 && obstructionIndicatorElement) {
            obstructionIndicatorElement.style.display = 'none';
          }

          // Calculate curse modifiers (but don't apply yet)
          let finalRoll = result;
          const statModifier = window.CombatState.getStatModifier();

          // Check for Curse of Failure
          const failureCurses = CurseManager.findByType('failure');
          let failureDamage = 0;
          if (failureCurses.length > 0 && result === 1) {
            // Curse of Failure: Roll of 1 is auto-miss and deals damage
            failureDamage = failureCurses.reduce((sum, curse) =>
              sum + getPowerValue(curse.power, { Low: 2, Medium: 3, High: 4 }), 0
            );

            if (typeof calculateDamageReduction === 'function') {
              failureDamage = calculateDamageReduction(failureDamage);
            }

            // Treat roll as 0 for AC check (auto-miss)
            finalRoll = 0;
          }

          // Check for Curse of Weakness
          let cursePenalty = 0;
          let weaknessCurse = null;
          const weaknessCurses = CurseManager.findByType('weakness');
          if (weaknessCurses.length > 0) {
            weaknessCurse = weaknessCurses[0];
            cursePenalty = getPowerValue(weaknessCurse.power, { Low: 2, Medium: 3, High: 4 });
          }

          const totalRoll = finalRoll + statModifier - cursePenalty;
          const hit = totalRoll >= combat.enemy.armorClass;

          // Calculate what damage WOULD be dealt (but don't apply it)
          let calculatedDamage = 0;
          let damagePreview = null;
          if (hit) {
            calculatedDamage = combat.player.attack;
            // Preview what would happen with block
            const enemyBlock = combat.enemy.effects.block || 0;
            const blockConsumed = Math.min(enemyBlock, calculatedDamage);
            const healthLost = calculatedDamage - blockConsumed;
            damagePreview = { blockConsumed, healthLost };
          }

          // Store pending roll data
          pendingRolls[diceType] = {
            result: result,
            finalRoll: finalRoll,
            statModifier: statModifier,
            cursePenalty: cursePenalty,
            weaknessCurse: weaknessCurse,
            failureCurses: failureCurses,
            failureDamage: failureDamage,
            totalRoll: totalRoll,
            hit: hit,
            damage: calculatedDamage,
            damagePreview: damagePreview
          };

          // Display roll result (preview)
          resultDisplay.innerHTML = `
            <div style="background: rgba(0,0,0,0.5); padding: 8px; border-radius: 6px;">
              <p style="margin: 2px 0; font-size: 12px;">Dice: <strong>${result}</strong></p>
              <p style="margin: 2px 0; font-size: 12px; color: ${getStatColor(combat.enemy.stat)};">+ ${combat.enemy.stat}: <strong>${statModifier}</strong></p>
              ${cursePenalty > 0 ? `<p style="margin: 2px 0; font-size: 12px; color: #ff6666;">- Weakness: <strong>${cursePenalty}</strong></p>` : ''}
              ${failureDamage > 0 ? `<p style="margin: 2px 0; font-size: 12px; color: #ff6666;">⚠️ Failure: <strong>${failureDamage} dmg to you</strong></p>` : ''}
              <p style="margin: 4px 0 0 0; font-size: 16px; color: ${hit ? '#4CAF50' : '#ff6666'};"><strong>${hit ? 'HIT!' : 'MISS'} (${totalRoll}/${combat.enemy.armorClass})</strong></p>
            </div>
          `;

        } else {
          // Defense dice - calculate block that would be gained
          const blockGained = rollResult.result.total;
          const newBlockTotal = (combat.player.effects.block || 0) + blockGained;

          // Store pending roll data
          pendingRolls[diceType] = {
            blockGained: blockGained,
            newBlockTotal: newBlockTotal
          };

          // Display roll result (preview)
          resultDisplay.innerHTML = `
            <div style="background: rgba(0,0,0,0.5); padding: 8px; border-radius: 6px;">
              <p style="margin: 2px 0; font-size: 16px; color: #66ccff;"><strong>+${blockGained} 🛡️</strong></p>
              <p style="margin: 4px 0 0 0; font-size: 12px;">Block: ${newBlockTotal}</p>
            </div>
          `;
        }

        // Enable confirm and reroll buttons
        updateButtonStates(diceType, true, false);
      });

    } catch (error) {
      console.error('Error rolling dice:', error);
      addCombatLogMessage(error.message, 'danger');
    }
  }

  // Handle confirming a roll (executes the stored effect)
  function handleConfirm(diceType) {
    if (!pendingRolls[diceType]) {
      return; // No pending roll
    }

    const pending = pendingRolls[diceType];

    if (diceType === 'attack') {
      // Execute attack effects
      if (pending.failureDamage > 0) {
        addCombatLogMessage(`Rolled a 1! Curse of Failure activated!`, 'danger');
        combat.player.health = Math.max(0, combat.player.health - pending.failureDamage);
        gameState.health = combat.player.health;
        updateCombatUI();
        addCombatLogMessage(`Curse of Failure dealt ${pending.failureDamage} damage!`, 'danger');
      }

      // Remove Curse of Weakness if it was applied
      if (pending.weaknessCurse) {
        addCombatLogMessage(`Curse of Weakness: -${pending.cursePenalty}`, 'warning');
        gameState.activeCurses.splice(gameState.activeCurses.indexOf(pending.weaknessCurse), 1);
        updateCurseUI();
      }

      if (pending.hit) {
        // Apply damage through enemy's block
        const damageResult = window.CombatEffects.processDamageWithBlock(combat.enemy, pending.damage);

        addCombatLogMessage(`⚔️ Attack hit! (${pending.totalRoll} vs AC ${combat.enemy.armorClass})`, 'success');

        if (damageResult.blockConsumed > 0) {
          addCombatLogMessage(`💥 Dealt ${damageResult.healthLost} damage (${damageResult.blockConsumed} blocked)!`, 'success');
        } else {
          addCombatLogMessage(`💥 Dealt ${damageResult.healthLost} damage to ${combat.enemy.name}!`, 'success');
        }

        // Update UI to show enemy damage
        updateCombatUI();

        // Check if enemy is defeated
        if (combat.enemy.health <= 0) {
          setTimeout(() => {
            handleVictory();
          }, 500);
        }
      } else {
        addCombatLogMessage(`❌ Attack missed! (${pending.totalRoll} vs AC ${combat.enemy.armorClass})`, 'info');
      }

    } else {
      // Execute defense effects
      combat.player.effects.block = pending.newBlockTotal;
      addCombatLogMessage(`🛡️ Gained ${pending.blockGained} block! (Total: ${pending.newBlockTotal})`, 'info');
      updateCombatUI();
    }

    // Clear the pending roll
    pendingRolls[diceType] = null;

    // Disable both confirm and reroll buttons after confirming
    updateButtonStates(diceType, false, true);

    // Enable end turn button after confirming
    const endTurnBtn = document.getElementById('end-turn-btn');
    endTurnBtn.disabled = false;
    endTurnBtn.style.opacity = '1';
    endTurnBtn.style.cursor = 'pointer';
    endTurnBtn.style.background = 'linear-gradient(145deg, #4CAF50, #2E7D32)';
    endTurnBtn.style.color = 'white';
    endTurnBtn.style.borderColor = '#2E7D32';
  }

  // Handle rerolling a dice (costs reroll stat)
  function handleReroll(diceType) {
    if (!pendingRolls[diceType]) {
      return; // No pending roll
    }

    if (gameState.reroll <= 0) {
      addCombatLogMessage('No rerolls remaining!', 'warning');
      return;
    }

    // Consume one reroll
    gameState.reroll--;

    // Clear the pending roll
    pendingRolls[diceType] = null;

    // Disable buttons temporarily
    updateButtonStates(diceType, false, false);

    // Update reroll button text
    updateRerollButtonText();

    addCombatLogMessage(`🔄 Rerolling ${diceType} dice... (${gameState.reroll} rerolls left)`, 'info');

    // Trigger a new roll (this will refund the energy since we're rerolling)
    // First, refund the energy that was spent
    combat.player.energy = Math.min(combat.player.energy + 1, combat.player.maxEnergy);
    updateEnergyDisplay();

    // Now roll again (this will spend energy again)
    setTimeout(() => {
      handleDiceClick(diceType);
    }, 100);
  }

  // Setup end turn button
  document.getElementById('end-turn-btn').addEventListener('click', handleEndTurn);

  function handleEndTurn() {
    try {
      // Check if combat is still active
      const combat = window.CombatState.getCombatState();
      if (!combat) {
        console.warn('No active combat');
        return;
      }

      // Check if it's player's turn
      if (combat.phase !== 'player_turn') {
        console.warn('Not in player turn phase:', combat.phase);
        return;
      }

      const turnResult = window.CombatState.endPlayerTurn();

      // Update UI
      updateCombatUI();

      // Check combat result
      if (turnResult.phase === 'victory') {
        handleVictory();
      } else if (turnResult.phase === 'defeat') {
        handleDefeat();
      } else {
        // Continue to next turn
        startNextTurn();
      }

    } catch (error) {
      console.error('Error ending turn:', error);
      addCombatLogMessage(error.message, 'danger');
    }
  }

  function startNextTurn() {
    // Reset for next turn
    const currentCombat = window.CombatState.getCombatState();

    // Clear roll results
    document.getElementById('attack-roll-result').innerHTML = '';
    document.getElementById('defense-roll-result').innerHTML = '';

    // Clear pending rolls
    pendingRolls.attack = null;
    pendingRolls.defense = null;

    // Reset confirm and reroll buttons
    updateButtonStates('attack', false, false);
    updateButtonStates('defense', false, false);

    const endTurnBtn = document.getElementById('end-turn-btn');
    endTurnBtn.disabled = true;
    endTurnBtn.style.opacity = '0.5';
    endTurnBtn.style.cursor = 'not-allowed';
    endTurnBtn.style.background = 'linear-gradient(145deg, #555, #444)';
    endTurnBtn.style.color = '#888';
    endTurnBtn.style.borderColor = '#666';

    // Reset energy to max
    currentCombat.player.energy = currentCombat.player.maxEnergy;

    // Reset block to 0 at start of turn
    currentCombat.player.effects.block = 0;

    // Update energy display
    updateEnergyDisplay();
    updateCombatUI();

    // Re-create dice for next roll
    attackRenderer.createDice(currentCombat.dice.attack);
    defenseRenderer.createDice(currentCombat.dice.defense);
    enemyIntentRenderer.createDice(currentCombat.dice.enemy);

    // Show new enemy intent
    showEnemyIntent();
  }

  function updateCombatUI() {
    // Update player HP bar and text
    const playerHpPercent = (combat.player.health / combat.player.maxHealth) * 100;
    const playerHpBar = document.getElementById('player-hp-bar');
    if (playerHpBar) {
      playerHpBar.style.width = `${playerHpPercent}%`;
    }
    document.getElementById('player-hp').textContent = `${combat.player.health}/${combat.player.maxHealth}`;

    // Update player block display
    const playerBlockDisplay = document.getElementById('player-block-display');
    const playerBlockValue = document.getElementById('player-block-value');
    if (playerBlockDisplay && playerBlockValue) {
      const playerBlock = combat.player.effects.block || 0;
      if (playerBlock > 0) {
        playerBlockDisplay.style.display = 'flex';
        playerBlockValue.textContent = playerBlock;
      } else {
        playerBlockDisplay.style.display = 'none';
      }
    }

    // Update enemy HP bar and text
    const enemyHpPercent = (combat.enemy.health / combat.enemy.maxHealth) * 100;
    document.getElementById('enemy-hp-bar').style.width = `${enemyHpPercent}%`;
    document.getElementById('enemy-hp-text').textContent = `${Math.max(0, combat.enemy.health)}/${combat.enemy.maxHealth}`;

    // Update enemy block display
    const enemyBlockDisplay = document.getElementById('enemy-block-display');
    const enemyBlockValue = document.getElementById('enemy-block-value');
    if (enemyBlockDisplay && enemyBlockValue) {
      const enemyBlock = combat.enemy.effects.block || 0;
      if (enemyBlock > 0) {
        enemyBlockDisplay.style.display = 'flex';
        enemyBlockValue.textContent = enemyBlock;
      } else {
        enemyBlockDisplay.style.display = 'none';
      }
    }

    // Update effects displays
    updateEffectsDisplay('player-effects', combat.player.effects);
    updateEffectsDisplay('enemy-effects', combat.enemy.effects);

    // Update combat log
    updateCombatLog();

    // Update global health and sync with main UI
    StateMutator.setHealth(combat.player.health);

    // Update inventory to reflect any changes
    updateCombatInventory();

    // Update items bar
    populateItemsBar();
  }

  function updateEffectsDisplay(elementId, effects) {
    const container = document.getElementById(elementId);
    const descriptions = window.CombatEffects.getEffectDescriptions(effects);

    if (descriptions.length === 0) {
      container.innerHTML = '';
    } else {
      container.innerHTML = descriptions.map(desc =>
        `<p style="margin: 2px 0; color: #aaa;">${desc}</p>`
      ).join('');
    }
  }

  function updateCombatLog() {
    const logContainer = document.getElementById('combat-log-messages');
    if (!logContainer) return;

    const messages = combat.log; // Show all messages

    logContainer.innerHTML = messages.map(msg => {
      const color = msg.type === 'success' ? '#4CAF50' :
                    msg.type === 'danger' ? '#ff4444' :
                    msg.type === 'warning' ? '#ff9800' : '#aaa';

      return `<p style="margin: 5px 0; color: ${color}; line-height: 1.4;">${msg.message}</p>`;
    }).join('');

    // Scroll to bottom
    logContainer.scrollTop = logContainer.scrollHeight;
  }

  function addCombatLogMessage(message, type = 'info') {
    window.CombatState.addCombatLog(message, type);
    updateCombatLog();
  }

  function populateItemsBar() {
    const itemsContainer = document.getElementById('items-icons');

    if (!itemsContainer) {
      console.warn('Items container not found');
      return;
    }

    if (inventory.length === 0) {
      itemsContainer.innerHTML = '<span style="color: #666; font-size: 13px;">No items</span>';
      return;
    }

    itemsContainer.innerHTML = inventory.map((item, idx) => {
      let imageUrl = item.image && item.image.trim() !== ''
        ? item.image
        : 'https://via.placeholder.com/50?text=%3F';

      // Fix imgur URLs
      if (imageUrl.includes('imgur.com/') && !imageUrl.includes('i.imgur.com')) {
        imageUrl = imageUrl.replace('imgur.com/', 'i.imgur.com/');
        if (!imageUrl.match(/\.(png|jpg|jpeg|gif)$/i)) {
          imageUrl += '.png';
        }
      }

      const getRarityColor = (rarity) => {
        switch(rarity?.toLowerCase()) {
          case 'legendary': return '#ff6b00';
          case 'rare': return '#9b59b6';
          case 'uncommon': return '#4CAF50';
          case 'common': return '#aaa';
          default: return '#888';
        }
      };

      const rarityColor = getRarityColor(item.rarity);
      const isUsable = item.type === 'Usable';
      const canUse = isUsable && typeof canUseItem === 'function' && canUseItem(item);

      return `
        <div class="item-icon" data-item-index="${idx}" style="
          width: 50px;
          height: 50px;
          position: relative;
          border: 2px solid ${rarityColor};
          border-radius: 6px;
          background: rgba(0,0,0,0.5);
          cursor: pointer;
          transition: all 0.2s ease;
          ${!canUse && isUsable ? 'opacity: 0.5;' : ''}
        " onmouseenter="showCombatItemTooltip(event, ${idx})" onmouseleave="hideCombatItemTooltip()">
          <img src="${imageUrl}" style="
            width: 100%;
            height: 100%;
            object-fit: contain;
            border-radius: 4px;
          " alt="${item.name}" onerror="if(this.src!=='https://via.placeholder.com/50?text=%3F'){this.src='https://via.placeholder.com/50?text=%3F';}">
          ${item.quantity && item.quantity > 1 ? `
            <div style="
              position: absolute;
              bottom: 2px;
              right: 2px;
              background: rgba(0,0,0,0.9);
              color: white;
              padding: 1px 3px;
              border-radius: 3px;
              font-size: 9px;
              font-weight: bold;
              border: 1px solid #ffaa00;
            ">x${item.quantity}</div>
          ` : ''}
          ${(function() {
            if ((item.type || '').toLowerCase() !== 'incremental') return '';
            const cs = window.CombatEngine ? window.CombatEngine.getCombatState() : null;
            const inc = cs && cs.incrementals;
            let cur = 0, max = null;
            switch (item.name) {
              case 'Pen Nib':        cur = inc ? inc.attacksTotal % 10 : 0;      max = 10; break;
              case 'Nunchaku':       cur = inc ? inc.attacksTotal % 10 : 0;      max = 10; break;
              case 'Happy Flower':   cur = cs  ? (cs.turn - 1) % 3 : 0;         max = 3;  break;
              case 'Ornamental Fan': cur = inc ? inc.attacksThisTurn % 4 : 0;   max = 4;  break;
              case 'Shuriken':       cur = inc ? inc.attacksThisTurn % 3 : 0;   max = 3;  break;
            }
            if (max === null) return '';
            return '<div style="position:absolute;top:1px;left:1px;background:rgba(0,0,0,0.85);color:#ffcc44;padding:1px 3px;border-radius:3px;font-size:9px;font-weight:bold;border:1px solid #ffcc44;line-height:1.2;">' + cur + '/' + max + '</div>';
          })()}
        </div>
      `;
    }).join('');
  }

  function setupStatsPanel() {
    const statsPanel = document.getElementById('stats-panel');
    const viewStatsBtn = document.getElementById('view-stats-btn');
    const closeStatsBtn = document.getElementById('close-stats-btn');

    // Populate stats
    const statsContent = document.getElementById('all-stats-content');
    statsContent.innerHTML = `
      <div style="background: rgba(0,0,0,0.4); border: 2px solid #4CAF50; border-radius: 8px; padding: 15px;">
        <h4 style="margin: 0 0 12px 0; color: #4CAF50; font-size: 16px; border-bottom: 1px solid rgba(76,175,80,0.3); padding-bottom: 8px;">⚔️ Combat Stats</h4>
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">
          <div style="text-align: center; background: rgba(255,102,102,0.1); border: 1px solid #ff6666; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 11px; text-transform: uppercase;">Attack</p>
            <p style="margin: 4px 0 0 0; color: #ff6666; font-weight: bold; font-size: 20px;">${attack}</p>
          </div>
          <div style="text-align: center; background: rgba(76,175,80,0.1); border: 1px solid #4CAF50; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 11px; text-transform: uppercase;">Health</p>
            <p style="margin: 4px 0 0 0; color: #4CAF50; font-weight: bold; font-size: 20px;">${health}/${maxHealth}</p>
          </div>
        </div>
      </div>

      <div style="background: rgba(0,0,0,0.4); border: 2px solid #888; border-radius: 8px; padding: 15px;">
        <h4 style="margin: 0 0 12px 0; color: #aaa; font-size: 16px; border-bottom: 1px solid rgba(136,136,136,0.3); padding-bottom: 8px;">📊 Base Stats</h4>
        <div style="display: grid; grid-template-columns: 1fr 1fr; gap: 8px;">
          <div style="background: rgba(255,68,68,0.1); border: 1px solid #ff4444; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">Strength</p>
            <p style="margin: 3px 0 0 0; color: #ff6666; font-weight: bold; font-size: 18px;">${strength}</p>
          </div>
          <div style="background: rgba(76,175,80,0.1); border: 1px solid #4CAF50; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">Dexterity</p>
            <p style="margin: 3px 0 0 0; color: #4CAF50; font-weight: bold; font-size: 18px;">${dexterity}</p>
          </div>
          <div style="background: rgba(102,153,255,0.1); border: 1px solid #6699ff; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">Intelligence</p>
            <p style="margin: 3px 0 0 0; color: #6699ff; font-weight: bold; font-size: 18px;">${intelligence}</p>
          </div>
          <div style="background: rgba(255,102,255,0.1); border: 1px solid #ff66ff; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">Charisma</p>
            <p style="margin: 3px 0 0 0; color: #ff66ff; font-weight: bold; font-size: 18px;">${charisma}</p>
          </div>
          <div style="background: rgba(255,204,102,0.1); border: 1px solid #ffcc66; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">Luck</p>
            <p style="margin: 3px 0 0 0; color: #ffcc66; font-weight: bold; font-size: 18px;">${luck}</p>
          </div>
          <div style="background: rgba(255,255,255,0.05); border: 1px solid #888; border-radius: 6px; padding: 8px;">
            <p style="margin: 0; color: #aaa; font-size: 10px; text-transform: uppercase;">Reroll</p>
            <p style="margin: 3px 0 0 0; color: #aaa; font-weight: bold; font-size: 18px;">${reroll}</p>
          </div>
        </div>
      </div>
    `;

    // Toggle panel
    viewStatsBtn.addEventListener('click', () => {
      statsPanel.style.transform = 'translateX(0)';
    });

    closeStatsBtn.addEventListener('click', () => {
      statsPanel.style.transform = 'translateX(-100%)';
    });
  }

  function setupLogPanel() {
    const logPanel = document.getElementById('log-panel');
    const viewLogBtn = document.getElementById('view-log-btn');
    const closeLogBtn = document.getElementById('close-log-btn');

    // Toggle panel
    viewLogBtn.addEventListener('click', () => {
      logPanel.style.transform = 'translateX(0)';
    });

    closeLogBtn.addEventListener('click', () => {
      logPanel.style.transform = 'translateX(100%)';
    });
  }

  function setupItemTooltips() {
    // Tooltip functions are defined globally below
  }

  function updateCombatInventory() {
    // Now uses the items bar instead of separate inventory section
    populateItemsBar();
    return;

    // Old code below is no longer used
    const container = document.getElementById('combat-inventory-items');

    if (!container) return; // Element no longer exists in new layout

    if (inventory.length === 0) {
      container.innerHTML = '<div style="text-align: center; padding: 40px 20px; color: #666; font-size: 14px;">No items</div>';
      return;
    }

    // Use the same rendering logic as main gameplay
    container.innerHTML = inventory.map((item, idx) => {
      let imageUrl = item.image && item.image.trim() !== ''
        ? item.image
        : 'https://via.placeholder.com/70?text=%3F';

      // Fix imgur URLs
      if (imageUrl.includes('imgur.com/') && !imageUrl.includes('i.imgur.com')) {
        imageUrl = imageUrl.replace('imgur.com/', 'i.imgur.com/');
        if (!imageUrl.match(/\.(png|jpg|jpeg|gif)$/i)) {
          imageUrl += '.png';
        }
      }

      // Get rarity color
      const getRarityColor = (rarity) => {
        switch(rarity?.toLowerCase()) {
          case 'legendary': return '#ff6b00';
          case 'rare': return '#9b59b6';
          case 'uncommon': return '#4CAF50';
          case 'common': return '#aaa';
          default: return '#888';
        }
      };

      const rarityColor = getRarityColor(item.rarity);
      const isCharged = typeof isChargedItem === 'function' && isChargedItem(item);
      const isUsable = item.type === 'Usable' || isCharged;
      const canUse = isUsable && typeof canUseItem === 'function' && canUseItem(item);
      const isWeapon = item.type === 'Weapon';

      return `
        <div class="combat-item-container" style="
          display: flex;
          gap: 10px;
          background: rgba(0,0,0,0.3);
          border: 2px solid ${rarityColor};
          border-radius: 8px;
          padding: 8px;
          transition: all 0.2s ease;
          cursor: ${canUse ? 'pointer' : 'default'};
          opacity: ${canUse || !isUsable ? '1' : '0.6'};
        " ${canUse ? `onclick="useCombatItem(${idx})"` : ''}>
          <div style="flex-shrink: 0; position: relative;">
            <img src="${imageUrl}"
                 alt="${item.name}"
                 loading="lazy"
                 style="width: 60px; height: 60px; object-fit: contain; border-radius: 6px; background: #1a1a1a; padding: 2px; display: block;"
                 onerror="if(this.src!=='https://via.placeholder.com/70?text=%3F'){this.src='https://via.placeholder.com/70?text=%3F';}">
            ${item.quantity && item.quantity > 1 ? `
              <div style="
                position: absolute;
                top: 2px;
                right: 2px;
                background: rgba(0, 0, 0, 0.9);
                color: white;
                padding: 1px 4px;
                border-radius: 3px;
                font-size: 10px;
                font-weight: bold;
                border: 1px solid #ffaa00;
              ">x${item.quantity}</div>
            ` : ''}
            ${isWeapon && item.level && item.level > 1 ? `
              <div style="
                position: absolute;
                top: 2px;
                right: 2px;
                background: #ffaa44;
                color: #000;
                padding: 2px 4px;
                border-radius: 3px;
                font-size: 10px;
                font-weight: bold;
              ">Lv${item.level}</div>
            ` : ''}
          </div>
          <div style="flex: 1; min-width: 0;">
            <p style="margin: 0 0 4px 0; font-size: 13px; font-weight: bold; color: ${rarityColor}; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${item.name}</p>
            <p style="margin: 0 0 4px 0; font-size: 10px; color: #aaa; font-style: italic;">${item.type} • ${item.rarity}</p>
            <p style="margin: 0; font-size: 11px; color: #ccc; line-height: 1.3;">${item.description || item.effect || ''}</p>
            ${isUsable ? `
              <div style="margin-top: 6px;">
                <span style="
                  display: inline-block;
                  padding: 3px 8px;
                  font-size: 10px;
                  background: ${canUse ? '#4CAF50' : '#555'};
                  color: ${canUse ? 'white' : '#888'};
                  border-radius: 4px;
                  font-weight: bold;
                  text-transform: uppercase;
                ">
                  ${canUse ? '✓ Usable' : '✗ Cannot Use'}${item.uses && item.uses > 1 ? ` (${item.uses}x)` : ''}
                </span>
              </div>
            ` : ''}
          </div>
        </div>
      `;
    }).join('');

    // Also update the main gameplay inventory to keep them synced
    if (typeof updateInventory === 'function') {
      updateInventory();
    }
  }

  function handleVictory() {
    // Disable all combat buttons
    const endTurnBtn = document.getElementById('end-turn-btn');
    if (endTurnBtn) endTurnBtn.disabled = true;

    // Dispose all three dice renderers
    attackRenderer.dispose();
    defenseRenderer.dispose();
    enemyIntentRenderer.dispose();

    // Award rewards
    const goldMatch = enemy.successReward.match(/(\d+) Gold/);
    if (goldMatch) {
      const goldAmount = parseInt(goldMatch[1]);
      StateMutator.modifyGold(goldAmount);
    }

    // Trigger onEnemyDefeated effects
    if (typeof triggerOnEnemyDefeated === 'function') {
      triggerOnEnemyDefeated();
    }

    // Record encounter
    encounterHistory.push({
      type: 'combat',
      enemy: enemy.name,
      outcome: 'Victory',
      timestamp: new Date().toLocaleString()
    });
    updateEncounterHistory();

    // Increment difficulty immediately on combat win
    if (typeof markGameFinished === 'function') {
      markGameFinished(gameState.currentGame || 'Random Encounter');
    }

    saveCurrentGame();

    // Show victory screen
    setTimeout(() => {
      const _cardVictoryDifficulty = enemy.difficulty || 'Low';
      createGameModal(`
        <div style="text-align: center;">
          <h2 style="color: #4CAF50; font-size: 36px; margin: 20px 0;">⚔️ VICTORY!</h2>
          <h3>${enemy.name} defeated!</h3>
          <p style="color: #4CAF50; font-size: 18px; margin: 20px 0;">${enemy.successReward}</p>
          <button id="card-victory-continue-btn" style="
            padding: 15px 30px;
            background: #4CAF50;
            border: none;
            border-radius: 8px;
            color: white;
            cursor: pointer;
            font-weight: bold;
            font-size: 16px;
          ">Continue</button>
        </div>
      `);
      const _btn = document.getElementById('card-victory-continue-btn');
      if (_btn) {
        _btn.addEventListener('click', () => {
          closeGameModal();
          showPostCombatChoiceModal(_cardVictoryDifficulty);
        }, { once: true });
      }
    }, 500);

    window.CombatState.endCombat(true);
  }

  function handleDefeat() {
    // Dispose all three dice renderers
    attackRenderer.dispose();
    defenseRenderer.dispose();
    enemyIntentRenderer.dispose();

    // Clear items and curses on death
    inventory = [];
    if (gameState.activeCurses) {
      gameState.activeCurses = [];
    }

    // Record encounter
    encounterHistory.push({
      type: 'combat',
      enemy: enemy.name,
      outcome: 'Defeat',
      timestamp: new Date().toLocaleString()
    });
    updateEncounterHistory();

    window.CombatState.endCombat(false);

    // Show death screen
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
            ">🏠 Home</button>
            <button id="death-retry-btn" style="
              padding: 12px 24px;
              background: #d32f2f;
              border: 2px solid #f44336;
              border-radius: 8px;
              color: white;
              cursor: pointer;
              font-weight: bold;
              font-size: 16px;
            ">🔄 Try Again</button>
          </div>
        </div>
      `);

      document.getElementById('death-home-btn').onclick = () => {
        closeGameModal();
        updateInventory?.();
        updateCursesDisplay?.();
        updateActiveCursesList?.();
        updateGameStats?.();
        if (typeof clearAllArrows === 'function') {
          clearAllArrows();
        }
        document.getElementById('dungeon-screen').style.display = 'none';
        document.getElementById('main-menu').style.display = 'flex';
        const topBarRight = document.getElementById('top-bar-right');
        if (topBarRight) topBarRight.style.display = 'none';
      };

      document.getElementById('death-retry-btn').onclick = () => {
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
        const topBarRight = document.getElementById('top-bar-right');
        if (topBarRight) topBarRight.style.display = 'none';

        setTimeout(() => {
          document.getElementById('new-game-btn')?.click();
        }, 100);
      };
    }, 300);
  }

  // Helper function to get player image
  function getPlayerImagePath() {
    if (gameState && gameState.character && PLAYER_CHARACTERS[gameState.character]) {
      const character = PLAYER_CHARACTERS[gameState.character];
      return character.fullImage || character.icon;
    }
    return 'images/characters/full/default.png';
  }

  // Initial UI update
  updateCombatUI();
}

// Make showCombatModal available globally
window.showCombatModal = showCombatModal;

/**
 * New Dice-Based Combat Modal
 * Uses CombatEngine and CombatUI for the new combat system
 */
/**
 * Build a combat encounter using the weight system.
 * Total weight budgets:
 *   First combat ever: 2
 *   Low (rest): 4
 *   Medium (first of tier): 5   |  Medium (rest): 7
 *   High (first of tier): 8     |  High (rest): 10
 *   Insane (first of tier): 12  |  Insane (rest): 14
 * Max 4 enemies per encounter.
 * Enemy selection: pick a target weight 1..remaining equally, then pick a random
 * enemy with that weight from the eligible pool. Repeat until budget exhausted.
 */
function buildWeightedEncounter() {
  const gamesBeaten = gameState.totalGamesBeaten || 0;
  const combatsCompleted = gameState.totalCombatsCompleted || 0;

  // Determine current difficulty tier (Insane maps to its own combat tier)
  const _enc_thresholds = (typeof DIFFICULTY_THRESHOLDS !== 'undefined') ? DIFFICULTY_THRESHOLDS : { MEDIUM: 4, HARD: 8, INSANE: 12 };
  let currentTier;
  if (gamesBeaten >= _enc_thresholds.INSANE) currentTier = 'Insane';
  else if (gamesBeaten >= _enc_thresholds.HARD) currentTier = 'High';
  else if (gamesBeaten >= _enc_thresholds.MEDIUM) currentTier = 'Medium';
  else currentTier = 'Low';

  // Detect first combat of a new tier
  const isFirstCombatEver = combatsCompleted === 0;
  const tierChanged = gameState.lastDifficultyTier !== currentTier;
  const isFirstOfTier = isFirstCombatEver || tierChanged;

  // Budget based on tier + first/rest
  let budget;
  if (isFirstCombatEver) {
    budget = 2;
  } else if (currentTier === 'Low') {
    budget = 4;
  } else if (currentTier === 'Medium') {
    budget = isFirstOfTier ? 5 : 7;
  } else if (currentTier === 'High') {
    budget = isFirstOfTier ? 8 : 10;
  } else { // Insane
    budget = isFirstOfTier ? 12 : 14;
  }

  // Update tier tracking (will persist after combat)
  gameState.lastDifficultyTier = currentTier;

  // Build eligible pool: difficulty tier + game-type filter
  // Insane reuses the full High enemy pool (no separate Insane enemies exist)
  const tierOrder = ['Low', 'Medium', 'High'];
  const poolTier = currentTier === 'Insane' ? 'High' : currentTier;
  const maxTierIdx = tierOrder.indexOf(poolTier);

  // Determine which enemy type matches the current game's category
  const GAME_TYPE_TO_ENEMY_TYPE = {
    'Action': 'Strength',
    'Deckbuilding': 'Charisma',
    'Strategy': 'Intelligence',
    'Traditional': 'Dexterity',
  };
  const currentGameObj = typeof games !== 'undefined'
    ? games.find(g => g.name === gameState.currentGame)
    : null;
  const currentGameType = currentGameObj?.type || null;
  const requiredEnemyType = currentGameType ? (GAME_TYPE_TO_ENEMY_TYPE[currentGameType] || null) : null;

  // Base pool: tier-eligible enemies that match the game's enemy type
  // (falls back to all tier-eligible if no game type can be determined)
  let basePool = ENEMIES_DATA.filter(e =>
    e.weight !== null && e.difficulty !== null &&
    tierOrder.indexOf(e.difficulty) <= maxTierIdx &&
    (!requiredEnemyType || e.type === requiredEnemyType)
  );
  if (basePool.length === 0) {
    // Fallback: drop the type filter
    basePool = ENEMIES_DATA.filter(e =>
      e.weight !== null && e.difficulty !== null &&
      tierOrder.indexOf(e.difficulty) <= maxTierIdx
    );
  }

  // Specific Enemies setting: additionally restrict to enemies from the current game
  let eligiblePool = basePool;
  if (gameSettings.specificEnemies && gameState.currentGame) {
    const specificPool = basePool.filter(e => e.game === gameState.currentGame);
    // Only apply the game filter if it leaves at least one enemy
    if (specificPool.length > 0) eligiblePool = specificPool;
  }

  if (eligiblePool.length === 0) {
    console.error('No eligible enemies found for encounter');
    return null;
  }

  // Select enemies fairly
  const selectedEnemies = [];
  let remainingBudget = budget;
  const maxEnemies = 4;

  while (remainingBudget > 0 && selectedEnemies.length < maxEnemies) {
    // Find candidates that fit within remaining budget
    const fittingCandidates = eligiblePool.filter(e => e.weight <= remainingBudget);
    if (fittingCandidates.length === 0) break;

    // Determine available weight values (1 to max fitting weight), pick one equally
    const maxWeight = Math.max(...fittingCandidates.map(e => e.weight));
    const targetWeight = Math.floor(Math.random() * maxWeight) + 1;

    // Find enemies with exactly that weight; if none, find closest lower weight
    // Use ceiling so fractional-weight enemies (e.g. Fly at 0.5) map into the nearest integer bucket
    let weightCandidates = fittingCandidates.filter(e => Math.ceil(e.weight) === targetWeight);
    if (weightCandidates.length === 0) {
      // Pick any fitting enemy (fallback)
      weightCandidates = fittingCandidates;
    }

    const chosen = weightCandidates[Math.floor(Math.random() * weightCandidates.length)];
    selectedEnemies.push(chosen);
    remainingBudget -= chosen.weight;
  }

  return selectedEnemies;
}

function showDiceCombatModal() {
  if (!ENEMIES_DATA || ENEMIES_DATA.length === 0) {
    console.error('ENEMIES_DATA not loaded');
    return;
  }

  // Set phase to combat
  gameState.phase = 'combat';
  updateInventory();

  // Use pre-assigned enemies from the node modal if available, otherwise generate fresh
  const _preAssignedEnemies = gameState.choiceDetails?.[gameState.currentGame]?.enemies;
  const encounterEnemies = (_preAssignedEnemies && _preAssignedEnemies.length > 0)
    ? _preAssignedEnemies
    : buildWeightedEncounter();
  // Consume the pre-assigned slot so a retry generates fresh enemies
  if (_preAssignedEnemies && gameState.choiceDetails?.[gameState.currentGame]) {
    delete gameState.choiceDetails[gameState.currentGame].enemies;
  }
  if (!encounterEnemies || encounterEnemies.length === 0) {
    console.error('No matching enemies found');
    return;
  }

  // Append any event-spawned enemies (on top of the weight budget)
  if (Array.isArray(gameState.pendingSpawnEnemies) && gameState.pendingSpawnEnemies.length > 0) {
    for (const spawn of gameState.pendingSpawnEnemies) {
      const tmpl = ENEMIES_DATA.find(e => e.name.toLowerCase() === (spawn.enemy || '').toLowerCase());
      if (tmpl) {
        const count = spawn.min + Math.floor(Math.random() * (spawn.max - spawn.min + 1));
        for (let s = 0; s < count; s++) encounterEnemies.push(tmpl);
      }
    }
    gameState.pendingSpawnEnemies = [];
  }

  // Use the first enemy as the primary (multi-enemy support via array passed to initCombat)
  const enemyData = encounterEnemies[0];

  // Get character data
  const characterKey = selectedCharacter || gameState.character || 'Rodney';
  const characterData = PLAYER_CHARACTERS[characterKey];

  if (!characterData) {
    console.error('Character data not found for:', characterKey);
    // Fall back to old combat system
    showCombatModal();
    return;
  }

  // Merge player stats into character data
  characterData.stats = {
    strength: strength || 0,
    dexterity: dexterity || 0,
    intelligence: intelligence || 0,
    charisma: charisma || 0
  };
  characterData.health = health;
  characterData.maxHealth = maxHealth;
  characterData.reroll = gameState.reroll || reroll || 0;
  characterData.dash = gameState.dash || 0;

  // Get weapon data if equipped
  let weaponData = null;
  if (gameState.equippedWeapon && WEAPONS_DATA) {
    weaponData = WEAPONS_DATA.find(w => w.name === gameState.equippedWeapon.name);
  }

  // Get active allies from gameState
  const allies = (gameState.activeAllies || []).map(allyData => {
    // Each ally in gameState stores current HP, we need to merge with base data
    const baseAlly = ALLIES_DATA.find(a => a.name === allyData.name);
    if (!baseAlly) return null;
    return {
      ...baseAlly,
      currentHp: allyData.currentHp !== undefined ? allyData.currentHp : baseAlly.hp
    };
  }).filter(Boolean);

  // Clean up any lingering hover tooltips before combat starts
  if (typeof hideAllTooltips === 'function') hideAllTooltips();

  // Initialize combat with all encounter enemies
  const combatState = window.CombatEngine.initCombat(encounterEnemies, characterData, weaponData, allies);

  if (!combatState) {
    console.error('Failed to initialize combat');
    return;
  }

  // Apply statuses queued by pre-combat events (e.g. frail from event outcomes)
  if (Array.isArray(gameState.pendingCombatStatuses) && gameState.pendingCombatStatuses.length > 0) {
    for (const pending of gameState.pendingCombatStatuses) {
      if (combatState.player && combatState.player.statuses) {
        const key = pending.status.toLowerCase();
        combatState.player.statuses[key] = (combatState.player.statuses[key] || 0) + (pending.stacks || 1);
      }
    }
    gameState.pendingCombatStatuses = [];
  }

  // Full-screen combat — fill entire viewport, no modal chrome
  const existingModal = document.getElementById('game-modal');
  if (existingModal) existingModal.remove();
  const modal = document.createElement('div');
  modal.id = 'game-modal';
  const _topBar = document.getElementById('top-bar');
  const _topBarH = _topBar ? _topBar.offsetHeight : 0;
  modal.style.cssText = `position:fixed;top:${_topBarH}px;left:0;right:0;bottom:0;z-index:500;overflow:hidden;`;
  modal.innerHTML = `
    <div id="dice-combat-modal" style="width:100%;height:100%;display:flex;flex-direction:column;overflow:hidden;">
      <div id="dice-combat-content" style="flex:1;overflow:hidden;display:flex;flex-direction:column;min-height:0;"></div>
    </div>
  `;
  document.body.appendChild(modal);

  // Create tooltip element for item hover (reuse existing or create new)
  const existingTooltip = document.getElementById('combat-item-tooltip');
  if (!existingTooltip) {
    const tooltip = document.createElement('div');
    tooltip.id = 'combat-item-tooltip';
    tooltip.style.cssText = `
      position: fixed;
      display: none;
      background: linear-gradient(145deg, rgba(30,30,40,0.98), rgba(20,20,30,0.98));
      border: 3px solid #888;
      border-radius: 8px;
      padding: 12px 15px;
      max-width: 300px;
      z-index: 9000;
      pointer-events: auto;
      box-shadow: 0 4px 20px rgba(0,0,0,0.8);
    `;
    const tooltipContent = document.createElement('div');
    tooltipContent.id = 'combat-tooltip-content';
    tooltip.appendChild(tooltipContent);
    document.body.appendChild(tooltip);
  }

  // Render the combat UI
  const container = document.getElementById('dice-combat-content');
  if (container && window.CombatUI) {
    window.CombatUI.renderCombatUI(combatState, container);
  }

  // Override the checkCombatEnd to handle victory/defeat properly.
  // checkCombatEnd fires from many call sites in combat-ui.js (every player/
  // enemy action), and once `phase` flips to 'victory' it stays there — so
  // without a one-shot guard, two calls in the same frame would each schedule
  // a handleDiceCombatVictory, running markGameFinished twice and bumping
  // difficulty by 2 per win.
  const originalCheckEnd = window.CombatUI.checkCombatEnd;
  let _combatEndHandled = false;
  window.CombatUI.checkCombatEnd = function() {
    if (_combatEndHandled) return;
    const combat = window.CombatEngine.getCombatState();
    if (!combat) return;

    if (combat.phase === 'victory') {
      _combatEndHandled = true;
      setTimeout(() => {
        handleDiceCombatVictory(enemyData);
      }, 500);
    } else if (combat.phase === 'defeat') {
      _combatEndHandled = true;
      setTimeout(() => {
        handleDiceCombatDefeat(enemyData);
      }, 500);
    }
  };
}

/**
 * Handle victory in dice combat
 */
function handleDiceCombatVictory(enemy) {
  // Sync ally HP from combat state before ending
  const combatState = window.CombatEngine.getCombatState();
  if (combatState && combatState.allies) {
    combatState.allies.forEach(ally => {
      if (ally.isAlive) {
        updateAllyHp(ally.name, ally.health);
      } else {
        // Ally died in combat
        dismissAlly(ally.name);
      }
    });
  }

  // Cleanup 3D dice renderers
  if (window.CombatUI && window.CombatUI.cleanup3DDice) {
    window.CombatUI.cleanup3DDice();
  }

  // Hide all floating combat tooltips
  ['enemy-pattern-tooltip', 'combat-status-tooltip', 'combat-card-tooltip'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.style.display = 'none';
  });

  window.CombatEngine.endCombat(true);
  gameState.phase = 'selection'; // allow scrolls/items outside combat
  gameState.totalCombatsCompleted = (gameState.totalCombatsCompleted || 0) + 1;

  // Award gold based on difficulty tier
  const goldAmounts = { 'Low': 10, 'Medium': 15, 'High': 25, 'Insane': 35 };
  const goldReward = goldAmounts[enemy.difficulty] || 10;
  StateMutator.modifyGold(goldReward);

  // Trigger onEnemyDefeated effects
  if (typeof triggerOnEnemyDefeated === 'function') {
    triggerOnEnemyDefeated();
  }

  // Record enemy defeated for collection stats
  if (typeof recordEnemyDefeated === 'function') {
    recordEnemyDefeated(enemy.name);
  }

  // Record encounter
  encounterHistory.push({
    type: 'combat',
    enemy: enemy.name,
    outcome: 'Victory',
    timestamp: new Date().toLocaleString()
  });
  updateEncounterHistory();

  // Increment difficulty immediately on combat win
  if (typeof markGameFinished === 'function') {
    markGameFinished(gameState.currentGame || 'Random Encounter');
  }

  // Award one random potion or scroll (always runs; try/catch prevents silent failures)
  let lootIcon = '', lootDisplayName = '', lootDisplayRarity = '';
  try {
    const lootReward = window.selectRandomPotionOrScroll();
    window.addScrollOrPotionToLoot(lootReward);
    if (lootReward.type === 'scroll') {
      const _scrollPath = typeof getScrollImagePath === 'function' ? getScrollImagePath(lootReward) : 'images/scrolls/Unidentified.png';
      lootIcon = `<img src="${_scrollPath}" style="width:56px;height:56px;object-fit:contain;" onerror="this.style.display='none'">`;
      lootDisplayName = typeof getScrollDisplayName === 'function' ? getScrollDisplayName(lootReward.name) : 'Unidentified Scroll';
    } else {
      const _potionPath = typeof getPotionImagePath === 'function' ? getPotionImagePath(lootReward) : 'images/potions/Unidentified.png';
      lootIcon = `<img src="${_potionPath}" style="width:56px;height:56px;object-fit:contain;" onerror="this.style.display='none'">`;
      lootDisplayName = typeof getPotionDisplayName === 'function' ? getPotionDisplayName(lootReward.name) : 'Unidentified Potion';
    }
    lootDisplayRarity = lootReward.rarity || '';
    encounterHistory.push({
      type: 'loot',
      name: lootDisplayName,
      rarity: lootDisplayRarity,
      timestamp: new Date().toLocaleString()
    });
    if (typeof updateEncounterHistory === 'function') updateEncounterHistory();
  } catch (e) {
    console.error('Failed to award post-combat loot:', e);
  }

  saveCurrentGame();

  const difficulty = enemy.difficulty || 'Low';
  showVictoryScreen(enemy.name, goldReward, lootIcon, lootDisplayName, lootDisplayRarity, difficulty);
}

/**
 * Show post-combat choice modal (Rest / Smith / Shop / Movement Event).
 * Each option can only be used once per difficulty tier per run.
 * @param {string} difficulty - 'Low' | 'Medium' | 'High'
 */
function showPostCombatChoiceModal(difficulty) {
  // Pull every panel back into sync before showing post-combat options —
  // ensures Smith / Shop see the deck and inventory exactly as they are now,
  // including cards added by the just-completed combat or its rewards.
  if (typeof refreshAllUI === 'function') refreshAllUI();
  const tier = difficulty || 'Low';

  // Use the 2 pre-assigned options from the node modal if available for this game
  const preAssigned = gameState.choiceDetails?.[gameState.currentGame]?.postCombatOptions || null;

  const optionData = [
    {
      key: 'rest',
      label: 'Rest',
      icon: '🛌',
      desc: 'Heal 33% of your max health.',
      color: '#4CAF50',
      action: () => {
        const heal = Math.floor(maxHealth * 0.33);
        StateMutator.modifyHealth(heal);
        if (typeof saveCurrentGame === 'function') saveCurrentGame();
        closeGameModal();
        if (typeof createNotification === 'function') createNotification(`Rested: +${heal} Health`, '#4CAF50', '🛌');
        if (window._postcombatOnComplete) { const cb = window._postcombatOnComplete; window._postcombatOnComplete = null; cb(); }
      }
    },
    {
      key: 'smith',
      label: 'Smith',
      icon: '⚒️',
      desc: 'Choose 1 card from your deck to upgrade for free.',
      color: '#FF9800',
      action: () => {
        closeGameModal();
        showSmithChoiceModal();
      }
    },
    {
      key: 'shop',
      label: 'Shop',
      icon: '🛒',
      desc: 'Visit the shop to buy items.',
      color: '#FFD700',
      action: () => {
        closeGameModal();
        // Reset shop state so fresh items appear
        gameState.currentShopItems = null;
        gameState.shopRerollCount = 0;
        gameState.shopUpgradesUsed = 0;
        gameState.shopRemovesUsed = 0;
        if (typeof showShopModal === 'function') showShopModal();
      }
    },
    {
      key: 'movement',
      label: 'Movement Event',
      icon: '🗺️',
      desc: 'A special event that helps you navigate difficult terrain. (Coming soon)',
      color: '#9b59b6',
      action: () => {
        closeGameModal();
        if (typeof createNotification === 'function') createNotification('Movement Event coming soon!', '#9b59b6', '🗺️');
        if (window._postcombatOnComplete) { const cb = window._postcombatOnComplete; window._postcombatOnComplete = null; cb(); }
      }
    }
  ];

  // Filter to only the 2 pre-assigned options if the node modal set them
  const _filtered = preAssigned ? optionData.filter(o => preAssigned.includes(o.key)) : optionData;
  const visibleOptions = _filtered.length >= 2 ? _filtered : optionData;

  const buttonsHTML = visibleOptions.map(opt => `
      <div style="
        background: #2d2d2d;
        border: 2px solid ${opt.color};
        border-radius: 12px;
        padding: 20px;
        cursor: pointer;
        transition: transform 0.15s, box-shadow 0.15s;
        text-align: center;
        min-width: 160px;
        max-width: 200px;
        onmouseenter="this.style.transform='translateY(-4px)'; this.style.boxShadow='0 6px 20px ${opt.color}66'"
      "
      onclick="window._postcombatUseOption('${opt.key}', '${tier}')"
      id="postcombat-opt-${opt.key}">
        <div style="font-size:36px;margin-bottom:10px;">${opt.icon}</div>
        <div style="font-weight:bold;color:white;font-size:15px;margin-bottom:8px;">${opt.label}</div>
        <div style="color:#aaa;font-size:12px;line-height:1.4;">${opt.desc}</div>
      </div>
    `).join('');

  // Register option handler globally (modal scope)
  window._postcombatUseOption = (key, t) => {
    if (typeof saveCurrentGame === 'function') saveCurrentGame();
    const opt = optionData.find(o => o.key === key);
    if (opt) opt.action();
  };

  createGameModal(`
    <div style="text-align:center; padding:24px; max-width:920px;">
      <h2 style="color:#FFD700; margin-top:0; margin-bottom:6px;">After Battle</h2>
      <p style="color:#aaa; font-size:13px; margin-bottom:20px;">Choose your reward.</p>
      <div style="display:flex; gap:16px; justify-content:center; flex-wrap:wrap; margin-bottom:20px;">
        ${buttonsHTML}
      </div>
      <button onclick="closeGameModal();if(window._postcombatOnComplete){var _cb=window._postcombatOnComplete;window._postcombatOnComplete=null;_cb();}" style="
        padding:10px 30px; background:#444; border:none; border-radius:8px;
        color:#aaa; cursor:pointer; font-size:13px;
      ">Skip</button>
    </div>
  `);
}

/**
 * Show the Smith upgrade modal — player picks up to 2 cards to upgrade for free.
 */
function showSmithChoiceModal() {
  // Refresh UI + read fresh state — a card collected from the same combat's
  // loot tile lives in gameState.deck by now and must be reflected here.
  if (typeof refreshAllUI === 'function') refreshAllUI();
  // Include starter cards from character's starting deck that haven't been smith-upgraded yet
  const upgradedStarting = gameState.upgradedStartingCards || {};
  const charKey = gameState.character;
  const charData = (charKey && typeof PLAYER_CHARACTERS !== 'undefined') ? PLAYER_CHARACTERS[charKey] : null;
  const startingEntries = (charData && charData.startingDeck) ? charData.startingDeck : [];

  const startingUpgradeable = [];
  startingEntries.forEach(entry => {
    const template = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.find(c => c.name === entry.cardName) : null;
    if (template && template.canUpgrade) {
      const totalCount   = entry.count || 1;
      const upgradedCount = upgradedStarting[entry.cardName] || 0;
      const remaining    = totalCount - upgradedCount;
      for (let i = 0; i < remaining; i++) {
        startingUpgradeable.push({ ...template, _isStarting: true });
      }
    }
  });

  const collectedUpgradeable = (gameState.deck || []).filter(c => c.canUpgrade && !c.upgraded);
  const upgradeable = [...startingUpgradeable, ...collectedUpgradeable];

  if (upgradeable.length === 0) {
    if (typeof createNotification === 'function') createNotification('No upgradeable cards in deck!', '#FF9800', '⚒️');
    return;
  }

  const MAX_UPGRADES = 1;
  const selectedIndices = new Set();

  const rarityCol = r => {
    if (r === 'Rare') return 'var(--color-rare)';
    if (r === 'Uncommon') return 'var(--color-uncommon)';
    return 'var(--color-common)';
  };

  // Build each card HTML once — selection state toggled in-place via DOM
  const cardsHTML = upgradeable.map((card, idx) => {
    const rc = rarityCol(card.rarity);
    const upgDesc = card.upgradedDescription
      ? `<div class="smith-upgrade-block">
           <div class="smith-upgrade-label">▶ Upgraded</div>
           <div class="smith-upgrade-cost">${card.upgradedCost != null ? `Cost: ${card.upgradedCost}` : `Cost: ${card.cost}`}</div>
           <div class="smith-upgrade-desc">${card.upgradedDescription}</div>
         </div>`
      : `<div class="smith-upgrade-block" style="color:#555;font-size:10px;font-style:italic;">No upgrade available</div>`;

    const _smithArtHTML = card.imageUrl
      ? `<img src="${card.imageUrl}" alt="${card.name}"
             style="width:72px;height:72px;object-fit:contain;margin-bottom:6px;"
             onerror="this.style.display='none'">`
      : ((card.type || '').toLowerCase() === 'dice'
          ? `<div style="width:72px;height:72px;display:flex;align-items:center;justify-content:center;font-size:48px;margin-bottom:6px;">🎲</div>`
          : `<div style="width:72px;height:72px;margin-bottom:6px;"></div>`);

    return `
      <div class="smith-card-option" data-smith-idx="${idx}"
           style="border:2px solid #555;">
        ${_smithArtHTML}
        <div style="font-weight:bold;font-size:13px;color:white;text-align:center;margin-bottom:2px;">${card.name}</div>
        <div style="font-size:10px;color:${rc};margin-bottom:6px;">${card.rarity} · ${card.type}</div>

        <div class="smith-current-block">
          <div style="font-size:10px;color:#888;margin-bottom:2px;">Current — Cost: ${card.cost}</div>
          <div style="font-size:11px;color:#ccc;line-height:1.4;">${card.description}</div>
        </div>

        ${upgDesc}

        <div class="smith-selected-badge" style="display:none;">✓ Selected</div>
      </div>
    `;
  }).join('');

  createGameModal(`
    <div style="text-align:center; padding:20px; max-width:960px;">
      <h2 style="color:#FF9800; margin-top:0; margin-bottom:4px;">⚒️ Smith</h2>
      <p style="color:#aaa; font-size:13px; margin-bottom:16px;">
        Select up to ${MAX_UPGRADES} cards to upgrade for free.
        <span id="smith-counter" style="color:#FF9800; font-weight:bold;">0/${MAX_UPGRADES} selected</span>
      </p>
      <div style="display:flex; gap:12px; flex-wrap:wrap; justify-content:center; margin-bottom:20px;">
        ${cardsHTML}
      </div>
      <div style="display:flex; gap:10px; justify-content:center;">
        <button id="smith-confirm-btn" disabled style="
          padding:10px 28px; background:#555; border:none; border-radius:8px;
          color:#999; cursor:not-allowed; font-weight:bold; font-size:14px;
          transition: background 0.15s, color 0.15s;
        ">Upgrade (0)</button>
        <button onclick="closeGameModal();if(window._postcombatOnComplete){var _cb=window._postcombatOnComplete;window._postcombatOnComplete=null;_cb();}" style="
          padding:10px 24px; background:#333; border:1px solid #555; border-radius:8px;
          color:#aaa; cursor:pointer; font-size:14px;
        ">Cancel</button>
      </div>
    </div>
  `);

  // Update selection visuals without re-rendering the modal
  function updateSmithUI() {
    document.querySelectorAll('.smith-card-option').forEach(el => {
      const idx = parseInt(el.dataset.smithIdx);
      const sel = selectedIndices.has(idx);
      el.style.borderColor  = sel ? '#FF9800' : '#555';
      el.style.background   = sel ? '#2a1a00' : '#2d2d2d';
      el.querySelector('.smith-selected-badge').style.display = sel ? 'block' : 'none';
    });
    const count = selectedIndices.size;
    const counter = document.getElementById('smith-counter');
    if (counter) counter.textContent = `${count}/${MAX_UPGRADES} selected`;
    const btn = document.getElementById('smith-confirm-btn');
    if (btn) {
      btn.disabled      = count === 0;
      btn.textContent   = `Upgrade (${count})`;
      btn.style.background = count > 0 ? '#FF9800' : '#555';
      btn.style.color      = count > 0 ? 'white'   : '#999';
      btn.style.cursor     = count > 0 ? 'pointer' : 'not-allowed';
    }
  }

  document.querySelectorAll('.smith-card-option').forEach(el => {
    el.addEventListener('click', () => {
      const idx = parseInt(el.dataset.smithIdx);
      if (selectedIndices.has(idx)) {
        selectedIndices.delete(idx);
      } else if (selectedIndices.size < MAX_UPGRADES) {
        selectedIndices.add(idx);
      }
      updateSmithUI();
    });
  });

  document.getElementById('smith-confirm-btn').addEventListener('click', () => {
    let upgradeCount = 0;
    selectedIndices.forEach(idx => {
      const card = upgradeable[idx];
      if (card._isStarting) {
        if (!gameState.upgradedStartingCards) gameState.upgradedStartingCards = {};
        gameState.upgradedStartingCards[card.name] = (gameState.upgradedStartingCards[card.name] || 0) + 1;
        upgradeCount++;
      } else {
        const deckIdx = gameState.deck.findIndex(c => c === card);
        if (deckIdx !== -1) {
          gameState.deck[deckIdx].upgraded = true;
          if (gameState.deck[deckIdx].upgradedDescription) {
            gameState.deck[deckIdx].description = gameState.deck[deckIdx].upgradedDescription;
          }
          if (gameState.deck[deckIdx].upgradedCost !== null && gameState.deck[deckIdx].upgradedCost !== undefined) {
            gameState.deck[deckIdx].cost = gameState.deck[deckIdx].upgradedCost;
          }
          upgradeCount++;
        }
      }
    });
    if (typeof saveCurrentGame === 'function') saveCurrentGame();
    closeGameModal();
    if (typeof refreshAllUI === 'function') refreshAllUI();
    if (typeof createNotification === 'function') {
      createNotification(`Upgraded ${upgradeCount} card${upgradeCount !== 1 ? 's' : ''}!`, '#FF9800', '⚒️');
    }
    if (window._postcombatOnComplete) { const cb = window._postcombatOnComplete; window._postcombatOnComplete = null; cb(); }
  });
}

/**
 * Handle defeat in dice combat
 */
function handleDiceCombatDefeat(enemy) {
  // Cleanup 3D dice renderers
  if (window.CombatUI && window.CombatUI.cleanup3DDice) {
    window.CombatUI.cleanup3DDice();
  }

  // Hide all floating combat tooltips
  ['enemy-pattern-tooltip', 'combat-status-tooltip', 'combat-card-tooltip'].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.style.display = 'none';
  });

  window.CombatEngine.endCombat(false);
  gameState.phase = 'selection'; // allow scrolls/items outside combat

  // Clear items, curses, and allies on death
  inventory = [];
  if (gameState.activeCurses) {
    gameState.activeCurses = [];
  }
  if (gameState.activeAllies) {
    gameState.activeAllies = [];
  }

  // Record player killed by enemy for collection stats
  if (typeof recordPlayerKilledBy === 'function') {
    recordPlayerKilledBy(enemy.name);
  }

  // Record encounter
  encounterHistory.push({
    type: 'combat',
    enemy: enemy.name,
    outcome: 'Defeat',
    timestamp: new Date().toLocaleString()
  });
  updateEncounterHistory();

  // Show death screen
  createGameModal(`
    <div style="text-align: center; padding: 30px;">
      <h1 style="color: #ff4444; font-size: 48px; margin: 20px 0;">YOU DIED</h1>
      <p style="color: #aaa; font-size: 18px; margin: 20px 0;">Defeated by ${enemy.name}</p>
      <div style="margin-top: 30px; display: flex; gap: 15px; justify-content: center;">
        <button id="dice-death-home-btn" style="
          padding: 12px 24px;
          background: #444;
          border: 2px solid #666;
          border-radius: 8px;
          color: white;
          cursor: pointer;
          font-weight: bold;
          font-size: 16px;
        ">Home</button>
        <button id="dice-death-retry-btn" style="
          padding: 12px 24px;
          background: #d32f2f;
          border: 2px solid #f44336;
          border-radius: 8px;
          color: white;
          cursor: pointer;
          font-weight: bold;
          font-size: 16px;
        ">Try Again</button>
      </div>
    </div>
  `);

  document.getElementById('dice-death-home-btn').onclick = () => {
    closeGameModal();
    updateInventory?.();
    updateCursesDisplay?.();
    if (typeof clearAllArrows === 'function') clearAllArrows();
    document.getElementById('dungeon-screen').style.display = 'none';
    document.getElementById('main-menu').style.display = 'flex';
    const topBarRight = document.getElementById('top-bar-right');
    if (topBarRight) topBarRight.style.display = 'none';
  };

  document.getElementById('dice-death-retry-btn').onclick = () => {
    closeGameModal();
    if (typeof clearAllArrows === 'function') clearAllArrows();
    document.getElementById('dungeon-screen').style.display = 'none';
    document.getElementById('main-menu').style.display = 'flex';
    const topBarRight = document.getElementById('top-bar-right');
    if (topBarRight) topBarRight.style.display = 'none';
    setTimeout(() => {
      document.getElementById('new-game-btn')?.click();
    }, 100);
  };
}

if (typeof window !== 'undefined') {
  window.showCombatModal           = showCombatModal;
  window.buildWeightedEncounter    = buildWeightedEncounter;
  window.showDiceCombatModal       = showDiceCombatModal;
  window.handleDiceCombatVictory   = handleDiceCombatVictory;
  window.showPostCombatChoiceModal = showPostCombatChoiceModal;
  window.showSmithChoiceModal      = showSmithChoiceModal;
  window.handleDiceCombatDefeat    = handleDiceCombatDefeat;
}
