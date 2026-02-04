/**
 * Combat UI - Renders the new dice-based combat interface
 * Works with CombatEngine to display:
 * - Player dice pool with 3D dice using DiceRendererInstance
 * - Enemy intents with images
 * - Status effects
 * - Spellbook
 * - Targeting interface
 */

// Store active dice renderers for cleanup
let activeDiceRenderers = {};
let enemyDiceRenderers = {};
let lastEnemyDiceInitTurn = -1; // Track which turn enemy dice were initialized
let rolledDiceStates = {}; // Track which dice have been rolled (to stop animation)

// Image cache for move icons
const moveImageCache = {};
let imagesPreloaded = false;

// Move type to image path mapping
const moveImagePaths = {
  'dmg': 'images/moves/Attack.png',
  'block': 'images/moves/Defense.png',
  'heal': 'images/moves/Health.png',
  'mana': 'images/moves/Mana.png',
  'inflict': 'images/moves/Status.png',
  'assassinate': 'images/moves/Assassinate.png',
  'vitality': 'images/moves/Vitality.png',
  // Statuses for inflict targets
  'burn': 'images/statuses/Burn.png',
  'poison': 'images/statuses/Poison.png',
  'dodge': 'images/statuses/Dodge.png',
  'power': 'images/statuses/Power.png',
  'frail': 'images/statuses/Frail.png',
  'thorns': 'images/statuses/Thorns.png',
  'oiled': 'images/statuses/Oiled.png',
  'ruptured': 'images/statuses/Ruptured.png',
  'confused': 'images/statuses/Confused.png',
  'barricade': 'images/statuses/Barricade.png',
  'fading': 'images/statuses/Fading.png',
  'shifting': 'images/statuses/Shifting.png',
  'formless': 'images/statuses/Formless.png',
  'forgetful': 'images/statuses/Forgetful.png',
  'ritual': 'images/statuses/Ritual.png',
  'multi_attack': 'images/statuses/MultiAttack.png'
};

/**
 * Preload move images for dice faces
 */
function preloadMoveImages() {
  if (imagesPreloaded) return Promise.resolve();

  const promises = Object.entries(moveImagePaths).map(([key, path]) => {
    return new Promise((resolve) => {
      const img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = () => {
        moveImageCache[key] = img;
        resolve();
      };
      img.onerror = () => {
        console.warn(`Failed to load image: ${path}`);
        resolve(); // Continue even if image fails
      };
      img.src = path;
    });
  });

  return Promise.all(promises).then(() => {
    imagesPreloaded = true;
  });
}

/**
 * Render the new combat UI
 * @param {Object} combat - Combat state from CombatEngine
 * @param {HTMLElement} container - Container element
 */
function renderCombatUI(combat, container) {
  if (!combat) return;

  const html = `
    <style>
      .combat-die:hover .dice-tooltip {
        display: block !important;
      }
      .combat-die {
        transition: transform 0.2s, box-shadow 0.2s;
      }
      .combat-die:hover {
        transform: translateY(-4px);
        box-shadow: 0 6px 16px rgba(0,0,0,0.4);
      }
      .enemy-card:hover {
        transform: scale(1.02);
        box-shadow: 0 0 12px rgba(255,215,0,0.4);
      }
      .die-roll-btn:hover, .die-confirm-btn:hover, .die-reroll-btn:hover {
        transform: scale(1.05);
      }
      /* Enemy dice tooltip on hover */
      .enemy-die-container:hover .enemy-dice-tooltip {
        display: block !important;
      }
      .enemy-die-container {
        transition: transform 0.2s;
      }
      .enemy-die-container:hover {
        transform: scale(1.05);
      }
      /* Crisp pixel art rendering */
      .pixel-image {
        image-rendering: pixelated;
        image-rendering: crisp-edges;
        -ms-interpolation-mode: nearest-neighbor;
      }
    </style>
    <!-- Outer container with combat log on the side -->
    <div style="
      display: flex;
      width: 100%;
      height: 100%;
      gap: 0;
      overflow: hidden;
      box-sizing: border-box;
    ">
      <!-- Combat Log - Outside main box -->
      <div id="combat-log-sidebar" style="
        width: 160px;
        background: rgba(20,15,10,0.95);
        border-right: 2px solid #333;
        padding: 8px;
        display: flex;
        flex-direction: column;
        flex-shrink: 0;
      ">
        <div style="
          font-size: 11px;
          font-weight: bold;
          color: #888;
          text-transform: uppercase;
          margin-bottom: 8px;
          padding-bottom: 5px;
          border-bottom: 1px solid #444;
        ">Combat Log</div>
        <div style="flex: 1; overflow-y: auto;">
          ${renderCombatLog(combat)}
        </div>
      </div>

      <!-- Main Combat Area -->
      <div id="new-combat-container" style="
        flex: 1;
        display: flex;
        flex-direction: column;
        background: linear-gradient(135deg, #1a1410 0%, #2a1810 100%);
        padding: 10px;
        gap: 8px;
        overflow: hidden;
        box-sizing: border-box;
      ">
        <!-- Top: Resources Bar -->
        ${renderResourcesBar(combat)}

        <!-- Combatants Row: Player | Intent | Enemy -->
        <div style="
          display: flex;
          gap: 10px;
          align-items: stretch;
          flex: 1;
          min-height: 0;
        ">
          <!-- Player Side -->
          <div style="flex: 1; display: flex; flex-direction: column; gap: 8px; min-width: 0; overflow-y: auto;">
            ${renderPlayerSection(combat)}
            ${renderAlliesSection(combat)}
          </div>

          <!-- Center: Enemy Intent Display - LARGER -->
          <div id="enemy-intent-panel" style="
            width: 220px;
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: flex-start;
            gap: 10px;
            flex-shrink: 0;
            background: rgba(0,0,0,0.3);
            border: 2px solid rgba(255,170,68,0.4);
            border-radius: 8px;
            padding: 12px;
            overflow-y: auto;
            ">
              <div style="
                font-size: 14px;
                font-weight: bold;
                color: #ffaa44;
                text-transform: uppercase;
                margin-bottom: 5px;
                display: flex;
                align-items: center;
                gap: 6px;
              ">
                <span style="font-size: 16px;">🎲</span>
                ENEMY INTENT
              </div>
              <div style="
                font-size: 11px;
                color: #888;
                margin-bottom: 4px;
              ">Turn ${combat.turn}</div>
              ${renderEnemyIntentCenter(combat)}
            </div>

          <!-- Enemy Side -->
          <div style="flex: 1; display: flex; flex-direction: column; gap: 8px; min-width: 0; overflow-y: auto;">
            ${renderEnemiesSection(combat)}
          </div>
        </div>

        <!-- Dice Area with End Turn/Dash buttons -->
        <div style="
          background: rgba(0,0,0,0.4);
          border: 2px solid #444;
          border-radius: 8px;
          padding: 10px;
          flex-shrink: 0;
          position: relative;
        ">
          <!-- End Turn / Dash buttons in top-right -->
          <div style="
            position: absolute;
            top: 8px;
            right: 8px;
            display: flex;
            gap: 8px;
            z-index: 10;
          ">
            <button id="combat-dash-btn" style="
              padding: 6px 12px;
              font-size: 12px;
              background: linear-gradient(145deg, #2196F3, #1565C0);
              border: 2px solid #42A5F5;
              border-radius: 6px;
              color: white;
              cursor: pointer;
              ${combat.player.dash > 0 ? '' : 'opacity: 0.5; cursor: not-allowed;'}
            ">Dash (${combat.player.dash})</button>
            <button id="combat-end-turn-btn" style="
              padding: 8px 16px;
              font-size: 14px;
              font-weight: bold;
              background: linear-gradient(145deg, #4CAF50, #2E7D32);
              border: 2px solid #66BB6A;
              border-radius: 8px;
              color: white;
              cursor: pointer;
              text-transform: uppercase;
            ">End Turn</button>
          </div>
          ${renderDiceArea(combat)}
        </div>

        <!-- Spellbook -->
        ${combat.spells && combat.spells.length > 0 ? `
          <div id="spellbook-container" style="
            background: rgba(0,0,0,0.4);
            border: 2px solid #9C27B0;
            border-radius: 8px;
            padding: 8px;
            max-height: 80px;
            overflow-y: auto;
            flex-shrink: 0;
          ">
            ${renderSpellbook(combat)}
          </div>
        ` : ''}
      </div>
    </div>
  `;

  container.innerHTML = html;
  attachCombatEventListeners(combat);
}


/**
 * Render resources bar (Energy, Mana, Rerolls)
 */
function renderResourcesBar(combat) {
  const p = combat.player;

  return `
    <div style="
      display: flex;
      justify-content: center;
      gap: 30px;
      padding: 10px;
      background: rgba(0,0,0,0.3);
      border-radius: 8px;
    ">
      <div style="display: flex; align-items: center; gap: 8px;">
        <span style="color: #FFD700; font-size: 20px;">⚡</span>
        <span style="color: #FFD700; font-weight: bold; font-size: 18px;">
          ${p.energy} / ${p.maxEnergy}
        </span>
        <span style="color: #aaa; font-size: 12px;">Energy</span>
      </div>
      <div style="display: flex; align-items: center; gap: 8px;">
        <span style="color: #9C27B0; font-size: 20px;">💎</span>
        <span style="color: #9C27B0; font-weight: bold; font-size: 18px;">
          ${p.mana} / ${p.maxMana}
        </span>
        <span style="color: #aaa; font-size: 12px;">Mana</span>
      </div>
      <div style="display: flex; align-items: center; gap: 8px;">
        <span style="color: #2196F3; font-size: 20px;">🔄</span>
        <span style="color: #2196F3; font-weight: bold; font-size: 18px;">
          ${p.rerolls}
        </span>
        <span style="color: #aaa; font-size: 12px;">Rerolls</span>
      </div>
      <div style="display: flex; align-items: center; gap: 8px;">
        <span style="color: #4CAF50; font-size: 20px;">❤️</span>
        <span style="color: #4CAF50; font-weight: bold; font-size: 18px;">
          ${p.health} / ${p.maxHealth}
        </span>
        <span style="color: #aaa; font-size: 12px;">Health</span>
      </div>
      ${p.block > 0 ? `
        <div style="display: flex; align-items: center; gap: 8px;">
          <span style="color: #78909C; font-size: 20px;">🛡️</span>
          <span style="color: #78909C; font-weight: bold; font-size: 18px;">
            ${p.block}
          </span>
          <span style="color: #aaa; font-size: 12px;">Block</span>
        </div>
      ` : ''}
    </div>
  `;
}

/**
 * Render player section with full image
 */
function renderPlayerSection(combat) {
  const p = combat.player;
  // Get player image from character data
  let playerImagePath = 'images/characters/Full/default.png';
  if (typeof gameState !== 'undefined' && gameState.character) {
    const characters = window.PLAYER_CHARACTERS || window.CHARACTERS_DATA;
    if (characters && characters[gameState.character]) {
      const char = characters[gameState.character];
      playerImagePath = char.fullImage || char.icon || playerImagePath;
    }
  }

  return `
    <div style="
      background: rgba(76,175,80,0.1);
      border: 2px solid rgba(76,175,80,0.4);
      border-radius: 10px;
      padding: 15px;
      text-align: center;
    ">
      <div style="font-size: 14px; font-weight: bold; color: #4CAF50; text-transform: uppercase; margin-bottom: 8px;">
        YOU
      </div>

      <!-- Player Image - LARGER -->
      <div style="
        width: 200px;
        height: 200px;
        margin: 0 auto 12px auto;
        border-radius: 8px;
        background: rgba(0,0,0,0.3);
        padding: 8px;
        border: 2px solid rgba(76,175,80,0.4);
        display: flex;
        align-items: center;
        justify-content: center;
      ">
        <img src="${playerImagePath}" class="pixel-image" style="
          width: 100%;
          height: 100%;
          image-rendering: pixelated;
          image-rendering: crisp-edges;
          -ms-interpolation-mode: nearest-neighbor;
          object-fit: contain;
        " alt="Player" onerror="this.style.display='none'">
      </div>

      <!-- Health Bar -->
      <div style="display: flex; align-items: center; justify-content: center; gap: 8px; margin-bottom: 8px;">
        ${p.block > 0 ? `
          <div style="
            position: relative;
            width: 40px;
            height: 40px;
            display: flex;
            align-items: center;
            justify-content: center;
          ">
            <div style="position: absolute; font-size: 40px; color: #66ccff; text-shadow: 0 0 8px rgba(102,204,255,0.5);">🛡️</div>
            <div style="
              position: relative;
              z-index: 1;
              font-size: 16px;
              font-weight: bold;
              color: white;
              text-shadow: -1px -1px 0 #000, 1px -1px 0 #000, -1px 1px 0 #000, 1px 1px 0 #000;
            ">${p.block}</div>
          </div>
        ` : ''}

        <div style="background: #2a2a2a; border-radius: 6px; height: 22px; width: 160px; position: relative; overflow: hidden; border: 2px solid #4CAF50;">
          <div style="
            background: linear-gradient(90deg, #4CAF50, #2E7D32);
            height: 100%;
            width: ${(p.health / p.maxHealth) * 100}%;
            transition: width 0.3s ease;
          "></div>
          <span style="
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            font-size: 12px;
            font-weight: bold;
            text-shadow: 0 0 4px black;
            color: white;
          ">${p.health}/${p.maxHealth}</span>
        </div>
      </div>

      ${renderStatusEffects(p.statuses, 'player')}
    </div>
  `;
}

/**
 * Render allies section
 */
function renderAlliesSection(combat) {
  if (!combat.allies || combat.allies.length === 0) return '';

  return `
    <div style="
      background: rgba(33,150,243,0.1);
      border: 2px solid rgba(33,150,243,0.4);
      border-radius: 10px;
      padding: 10px;
    ">
      <div style="font-size: 14px; font-weight: bold; color: #2196F3; margin-bottom: 8px;">
        ALLIES
      </div>
      <div style="display: flex; flex-wrap: wrap; gap: 10px;">
        ${combat.allies.map(ally => {
          const allyImagePath = ally.imageUrl || `images/allies/${ally.name.replace(/\s+/g, '')}.png`;
          return `
            <div style="
              background: rgba(0,0,0,0.3);
              border-radius: 6px;
              padding: 8px;
              min-width: 100px;
              ${!ally.isAlive ? 'opacity: 0.5;' : ''}
            ">
              <div style="display: flex; gap: 8px; align-items: center;">
                <img src="${allyImagePath}"
                  alt="${ally.name}"
                  onerror="this.style.display='none'"
                  style="
                    width: 40px;
                    height: 40px;
                    object-fit: contain;
                    image-rendering: pixelated;
                    border-radius: 4px;
                    background: rgba(0,0,0,0.3);
                  "
                />
                <div>
                  <div style="font-weight: bold; color: ${ally.isAlive ? '#fff' : '#666'};">
                    ${ally.name}
                  </div>
                  <div style="color: ${ally.isAlive ? '#4CAF50' : '#666'}; font-size: 14px;">
                    ❤️ ${ally.health}/${ally.maxHealth}
                  </div>
                </div>
              </div>
              ${ally.block > 0 ? `<div style="color: #78909C; margin-top: 4px;">🛡️ ${ally.block}</div>` : ''}
              ${renderStatusEffects(ally.statuses, ally.id)}
            </div>
          `;
        }).join('')}
      </div>
    </div>
  `;
}

/**
 * Render enemy intent in center panel with 3D dice
 */
function renderEnemyIntentCenter(combat) {
  const aliveEnemies = combat.enemies.filter(e => e.health > 0);

  if (aliveEnemies.length === 0) {
    return `<div style="color: #666; font-size: 14px;">No enemies</div>`;
  }

  return aliveEnemies.map((enemy, enemyIdx) => {
    const intent = enemy.currentIntent;
    if (!intent || intent.length === 0) {
      return `
        <div style="
          background: rgba(204,51,51,0.2);
          border: 2px solid #cc3333;
          border-radius: 8px;
          padding: 8px;
          text-align: center;
          width: 100%;
        ">
          <div style="font-size: 12px; color: #F44336; margin-bottom: 4px;">${enemy.name}</div>
          <div style="color: #888; font-size: 11px;">Waiting...</div>
        </div>
      `;
    }

    // Show the intent as 3D dice with hover tooltips
    return `
      <div style="
        background: rgba(204,51,51,0.2);
        border: 2px solid #cc3333;
        border-radius: 8px;
        padding: 8px;
        text-align: center;
        width: 100%;
      ">
        <div style="font-size: 12px; color: #F44336; margin-bottom: 6px;">${enemy.name}</div>
        <div style="display: flex; flex-wrap: wrap; gap: 6px; align-items: center; justify-content: center;">
          ${intent.map((i, dieIdx) => {
            const face = i.face;
            const diceId = `enemy-${enemy.id}-${dieIdx}`;
            const effect = face?.effects?.[0];
            const moveKey = effect?.move?.toLowerCase();
            const emoji = moveEmojis[moveKey] || effect?.move || '—';
            const value = effect?.value || 0;

            // Generate enemy dice tooltip showing all faces
            const enemyDiceTooltip = enemy.dice && enemy.dice.length > 0 ?
              generateEnemyDiceTooltip(enemy.dice, enemy.name) : '';

            return `
              <div class="enemy-die-container" style="
                display: flex;
                flex-direction: column;
                align-items: center;
                gap: 4px;
                position: relative;
              ">
                <!-- Tooltip showing all enemy dice faces -->
                <div class="enemy-dice-tooltip" style="
                  position: absolute;
                  bottom: 100%;
                  left: 50%;
                  transform: translateX(-50%);
                  background: rgba(20,20,25,0.95);
                  border: 2px solid #cc3333;
                  border-radius: 8px;
                  padding: 10px;
                  margin-bottom: 8px;
                  display: none;
                  z-index: 100;
                  min-width: 160px;
                  max-width: 220px;
                  box-shadow: 0 4px 12px rgba(0,0,0,0.5);
                ">
                  ${enemyDiceTooltip}
                </div>
                <!-- 3D Dice Container - LARGER -->
                <div id="enemy-dice-3d-${diceId}"
                     class="enemy-dice-3d-container"
                     data-enemy-id="${enemy.id}"
                     data-die-index="${dieIdx}"
                     data-face-index="${i.faceIndex}"
                     style="
                       width: 90px;
                       height: 90px;
                       background: #1a1410;
                       border-radius: 8px;
                       border: 2px solid #cc3333;
                       cursor: help;
                     ">
                </div>
                <!-- Effect label below dice -->
                <div style="
                  background: rgba(0,0,0,0.5);
                  padding: 2px 8px;
                  border-radius: 4px;
                  font-size: 12px;
                  font-weight: bold;
                  color: #fff;
                ">
                  ${face?.isBlank ? '—' : `${value} ${emoji}`}
                </div>
              </div>
            `;
          }).join('')}
        </div>
      </div>
    `;
  }).join('');
}

/**
 * Generate tooltip HTML for enemy dice faces with descriptions
 */
function generateEnemyDiceTooltip(faces, enemyName) {
  if (!faces || faces.length === 0) return '<div style="color: #666;">No dice data</div>';

  const facesHTML = faces.map((face, i) => {
    if (face.isBlank) {
      return `
        <div style="display: flex; align-items: center; gap: 6px; padding: 3px 4px; background: rgba(0,0,0,0.3); border-radius: 3px;">
          <span style="font-size: 14px; width: 20px; text-align: center;">—</span>
          <span style="color: #666; font-size: 11px;">Blank</span>
        </div>
      `;
    }

    const effect = face.effects && face.effects[0];
    if (!effect) return '';

    const moveKey = effect.move?.toLowerCase();
    const emoji = moveEmojis[moveKey] || '?';
    const value = effect.value || 0;
    const description = moveDescriptions[moveKey] || effect.move || 'Unknown';
    const target = effect.target ? ` (${effect.target})` : '';

    return `
      <div style="display: flex; align-items: center; gap: 6px; padding: 3px 4px; background: rgba(0,0,0,0.3); border-radius: 3px;">
        <span style="font-size: 14px; width: 20px; text-align: center;">${emoji}</span>
        <div style="flex: 1;">
          <span style="font-weight: bold; color: #fff; font-size: 11px;">${value} ${effect.move}${target}</span>
        </div>
      </div>
    `;
  }).join('');

  return `
    <div style="font-size: 11px; color: #F44336; margin-bottom: 6px; text-transform: uppercase; font-weight: bold;">${enemyName} - All Faces</div>
    <div style="display: flex; flex-direction: column; gap: 4px;">
      ${facesHTML}
    </div>
  `;
}

/**
 * Render enemies section
 */
function renderEnemiesSection(combat) {
  return `
    <div style="display: flex; flex-direction: column; gap: 10px;">
      ${combat.enemies.map(enemy => renderEnemyCard(enemy, combat)).join('')}
    </div>
  `;
}

/**
 * Render single enemy card with image and health bar
 */
function renderEnemyCard(enemy, combat) {
  const isDead = enemy.health <= 0;
  // Get enemy image path - prefer imageUrl from data, fallback to getEnemyImagePath
  const enemyImagePath = enemy.imageUrl
    ? enemy.imageUrl
    : (typeof getEnemyImagePath === 'function'
      ? getEnemyImagePath(enemy.name)
      : `images/enemies/${enemy.name.replace(/\s+/g, '')}.png`);

  const healthPercent = Math.max(0, (enemy.health / enemy.maxHealth) * 100);

  return `
    <div class="enemy-card" data-enemy-id="${enemy.id}" style="
      background: ${isDead ? 'rgba(0,0,0,0.3)' : 'rgba(244,67,54,0.1)'};
      border: 2px solid ${isDead ? '#333' : 'rgba(244,67,54,0.4)'};
      border-radius: 10px;
      padding: 15px;
      ${isDead ? 'opacity: 0.5;' : 'cursor: pointer;'}
      transition: all 0.2s;
      text-align: center;
    ">
      <!-- Enemy Name -->
      <div style="font-size: 18px; font-weight: bold; color: ${isDead ? '#666' : '#F44336'}; margin-bottom: 8px;">
        ${enemy.name}
      </div>

      <!-- Enemy Image - LARGER -->
      <div style="
        width: 160px;
        height: 160px;
        margin: 0 auto 12px auto;
        border-radius: 8px;
        background: rgba(0,0,0,0.3);
        padding: 8px;
        border: 2px solid ${isDead ? '#333' : 'rgba(244,67,54,0.4)'};
        display: flex;
        align-items: center;
        justify-content: center;
      ">
        <img src="${enemyImagePath}"
          alt="${enemy.name}"
          class="pixel-image"
          onerror="this.style.display='none'"
          style="
            width: 100%;
            height: 100%;
            object-fit: contain;
            image-rendering: pixelated;
            image-rendering: crisp-edges;
            -ms-interpolation-mode: nearest-neighbor;
          "
        />
      </div>

      <!-- Health and Block Bar -->
      <div style="display: flex; align-items: center; justify-content: center; gap: 8px; margin-bottom: 8px;">
        ${enemy.block > 0 ? `
          <div style="
            position: relative;
            width: 36px;
            height: 36px;
            display: flex;
            align-items: center;
            justify-content: center;
          ">
            <div style="position: absolute; font-size: 36px; color: #66ccff; text-shadow: 0 0 8px rgba(102,204,255,0.5);">🛡️</div>
            <div style="
              position: relative;
              z-index: 1;
              font-size: 14px;
              font-weight: bold;
              color: white;
              text-shadow: -1px -1px 0 #000, 1px -1px 0 #000, -1px 1px 0 #000, 1px 1px 0 #000;
            ">${enemy.block}</div>
          </div>
        ` : ''}

        <div style="background: #2a2a2a; border-radius: 6px; height: 20px; width: 140px; position: relative; overflow: hidden; border: 2px solid ${isDead ? '#666' : '#F44336'};">
          <div style="
            background: linear-gradient(90deg, #F44336, #c62828);
            height: 100%;
            width: ${healthPercent}%;
            transition: width 0.3s ease;
          "></div>
          <span style="
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            font-size: 11px;
            font-weight: bold;
            text-shadow: 0 0 4px black;
            color: white;
          ">${enemy.health}/${enemy.maxHealth}</span>
        </div>
      </div>

      ${renderStatusEffects(enemy.statuses, enemy.id)}
    </div>
  `;
}

/**
 * Render status effects for a target using PNG images
 */
function renderStatusEffects(statuses, targetId) {
  if (!statuses || Object.keys(statuses).length === 0) return '';

  const statusIcons = {
    'burn': '🔥',
    'poison': '☠️',
    'dodge': '💨',
    'power': '⚔️',
    'block': '🛡️',
    'frail': '💔',
    'thorns': '🌵',
    'oiled': '🛢️',
    'ruptured': '🩸',
    'confused': '😵',
    'ritual': '📿',
    'barricade': '🏰',
    'forgetful': '❓',
    'formless': '👻',
    'fading': '⏳',
    'shifting': '🔀',
    'multi_attack': '⚡'
  };

  // Status descriptions for tooltips
  const statusDescriptions = {
    'burn': 'Takes 3 damage per stack at turn start',
    'poison': 'Takes damage equal to stacks at turn start',
    'dodge': 'Negates next incoming attack',
    'power': 'Increases damage dealt',
    'block': 'Absorbs incoming damage',
    'frail': 'Takes double damage',
    'thorns': 'Deals damage to attackers',
    'oiled': 'Burns deal double damage',
    'ruptured': 'Takes 3 damage when dodging',
    'confused': 'Energy costs are randomized',
    'ritual': 'Gains Power each turn',
    'barricade': 'Block persists between turns',
    'forgetful': 'Cannot use abilities',
    'formless': 'Rerolls intent when hit',
    'fading': 'Dies when stacks reach 0',
    'shifting': 'Loses Power when hit',
    'multi_attack': 'Attacks multiple times'
  };

  const entries = Object.entries(statuses).filter(([k, v]) => v > 0);
  if (entries.length === 0) return '';

  return `
    <div style="display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px; justify-content: center;">
      ${entries.map(([status, stacks]) => {
        const imgPath = moveImagePaths[status];
        const description = statusDescriptions[status] || status;

        return `
          <div title="${status}: ${stacks}\n${description}" style="
            background: rgba(0,0,0,0.5);
            border: 1px solid rgba(255,255,255,0.2);
            border-radius: 6px;
            padding: 4px 8px;
            display: flex;
            align-items: center;
            gap: 5px;
            min-width: 50px;
          ">
            ${imgPath ?
              `<img src="${imgPath}" style="width: 24px; height: 24px; image-rendering: pixelated;" onerror="this.outerHTML='<span style=font-size:20px>${statusIcons[status] || '❔'}</span>'">` :
              `<span style="font-size: 20px;">${statusIcons[status] || '❔'}</span>`
            }
            <span style="color: #fff; font-weight: bold; font-size: 14px;">${stacks}</span>
          </div>
        `;
      }).join('')}
    </div>
  `;
}

/**
 * Render dice area with larger container
 */
function renderDiceArea(combat) {
  return `
    <div style="
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      justify-content: center;
      padding: 10px 0;
      min-height: 220px;
    ">
      ${combat.playerDice.map(die => renderDie(die, combat)).join('')}
    </div>
  `;
}

/**
 * Generate tooltip HTML for dice faces (simple version)
 */
function generateDiceTooltip(die) {
  if (!die.faces || die.faces.length === 0) return '';

  const facesHTML = die.faces.map((face, i) => {
    if (face.isBlank) {
      return `<div style="padding: 2px 6px; background: rgba(0,0,0,0.3); border-radius: 3px; color: #666;">—</div>`;
    }
    const effect = face.effects && face.effects[0];
    if (!effect) return `<div style="padding: 2px 6px;">?</div>`;

    const moveKey = effect.move?.toLowerCase();
    const emoji = moveEmojis[moveKey] || effect.move || '?';
    const value = effect.value || 0;

    return `<div style="padding: 2px 6px; background: rgba(0,0,0,0.3); border-radius: 3px;">${value} ${emoji}</div>`;
  }).join('');

  return facesHTML;
}

// Move descriptions for tooltips
const moveDescriptions = {
  'dmg': 'Deal damage to enemy',
  'block': 'Gain block (absorbs damage)',
  'heal': 'Restore health',
  'mana': 'Gain mana for spells',
  'reroll': 'Gain reroll charges',
  'inflict': 'Apply status to enemy',
  'get': 'Gain status effect',
  'cleanse': 'Remove debuffs',
  'spawn': 'Summon a creature',
  'alter': 'Transform into new form',
  'pain': 'Deal damage to self',
  'assassinate': 'Kill enemy if HP ≤ value',
  'vitality': 'Gain max health'
};

/**
 * Generate detailed tooltip HTML for dice faces with descriptions
 */
function generateDiceTooltipDetailed(die) {
  if (!die.faces || die.faces.length === 0) return '<div style="color: #666;">No faces</div>';

  const facesHTML = die.faces.map((face, i) => {
    if (face.isBlank) {
      return `
        <div style="display: flex; align-items: center; gap: 8px; padding: 4px 6px; background: rgba(0,0,0,0.3); border-radius: 4px;">
          <span style="font-size: 16px; width: 24px; text-align: center;">—</span>
          <span style="color: #666;">Blank face</span>
        </div>
      `;
    }

    const effect = face.effects && face.effects[0];
    if (!effect) return `<div style="padding: 4px 6px; color: #888;">Unknown effect</div>`;

    const moveKey = effect.move?.toLowerCase();
    const emoji = moveEmojis[moveKey] || '?';
    const value = effect.value || 0;
    const description = moveDescriptions[moveKey] || effect.move || 'Unknown';
    const target = effect.target ? ` (${effect.target})` : '';
    const addons = effect.addons && effect.addons.length > 0 ? ` [${effect.addons.join(', ')}]` : '';

    // Get status image path if available
    const statusImgPath = moveImagePaths[moveKey];
    const imgHtml = statusImgPath ?
      `<img src="${statusImgPath}" style="width: 20px; height: 20px; image-rendering: pixelated;" onerror="this.style.display='none'">` :
      `<span style="font-size: 16px;">${emoji}</span>`;

    return `
      <div style="display: flex; align-items: center; gap: 8px; padding: 4px 6px; background: rgba(0,0,0,0.3); border-radius: 4px;">
        <div style="width: 24px; text-align: center; flex-shrink: 0;">${imgHtml}</div>
        <div style="flex: 1;">
          <div style="font-weight: bold; color: #fff;">${value} ${effect.move}${target}</div>
          <div style="font-size: 10px; color: #aaa;">${description}${addons}</div>
        </div>
      </div>
    `;
  }).join('');

  return facesHTML;
}

/**
 * Render a single die with 3D container and tooltip
 */
function renderDie(die, combat) {
  const isAvailable = !die.isExhausted &&
    (die.source !== 'ally' || combat.allies.find(a => a.id === die.id)?.isAlive);

  // Dice can be rolled again after confirming (as long as player has energy)
  const canRoll = isAvailable && !die.isRolled && combat.player.energy >= (die.energyCost || 1);

  const borderColor = die.isRolled ? '#FFD700' :
    canRoll ? '#2196F3' : '#666';

  const sourceColor = die.source === 'character' ? '#cc6600' :
    die.source === 'weapon' ? '#888888' :
    die.source === 'ally' ? '#66ccff' : '#cc6600';

  return `
    <div class="combat-die" data-die-id="${die.id}" data-die-source="${die.source}" style="
      background: rgba(0,0,0,0.5);
      border: 3px solid ${borderColor};
      border-radius: 12px;
      padding: 12px;
      min-width: 180px;
      text-align: center;
      position: relative;
      ${!isAvailable ? 'opacity: 0.5;' : ''}
    ">
      <!-- Tooltip on hover showing all faces with descriptions -->
      <div class="dice-tooltip" style="
        position: absolute;
        bottom: 100%;
        left: 50%;
        transform: translateX(-50%);
        background: rgba(20,20,25,0.95);
        border: 2px solid #555;
        border-radius: 8px;
        padding: 10px;
        margin-bottom: 8px;
        display: none;
        z-index: 100;
        min-width: 180px;
        max-width: 250px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.5);
      ">
        <div style="font-size: 12px; color: #ffaa44; margin-bottom: 8px; text-transform: uppercase; font-weight: bold;">${die.name} - All Faces</div>
        <div style="display: flex; flex-direction: column; gap: 6px; font-size: 12px; color: #fff;">
          ${generateDiceTooltipDetailed(die)}
        </div>
      </div>

      <div style="font-size: 11px; color: #888; text-transform: uppercase; margin-bottom: 3px;">
        ${die.source}
      </div>
      <div style="font-size: 13px; font-weight: bold; color: #fff; margin-bottom: 8px;">
        ${die.name}
      </div>

      <!-- 3D Dice Container - BIGGER -->
      <div id="dice-3d-${die.id}" class="dice-3d-container" data-die-id="${die.id}"
        data-source-color="${sourceColor}"
        style="
          width: 140px;
          height: 140px;
          margin: 0 auto 8px auto;
          background: #1a1410;
          border-radius: 8px;
          cursor: ${canRoll ? 'pointer' : 'default'};
          position: relative;
        ">
        ${!die.isRolled && !activeDiceRenderers[die.id] ? `
          <div style="
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            color: #666;
            font-size: 14px;
            pointer-events: none;
          ">${canRoll ? 'Click to Roll' : 'Need Energy'}</div>
        ` : ''}
      </div>

      <!-- Result display (shown after roll) -->
      ${die.isRolled && die.currentFace ? `
        <div style="
          background: rgba(0,0,0,0.4);
          border-radius: 6px;
          padding: 6px;
          margin-bottom: 8px;
          font-size: 14px;
          font-weight: bold;
          color: #fff;
        ">
          ${die.currentFace.isBlank ? 'Blank' : die.currentFace.raw}
        </div>
      ` : ''}

      <!-- Buttons below dice: Reroll and Confirm side by side -->
      <div style="display: flex; gap: 6px; justify-content: center; flex-wrap: wrap; margin-top: 5px;">
        ${canRoll ? `
          <button class="die-roll-btn" data-die-id="${die.id}" style="
            padding: 10px 20px;
            background: linear-gradient(145deg, #2196F3, #1565C0);
            border: 2px solid #42A5F5;
            border-radius: 8px;
            color: white;
            cursor: pointer;
            font-weight: bold;
            font-size: 14px;
            text-transform: uppercase;
            box-shadow: 0 2px 8px rgba(33,150,243,0.4);
            transition: all 0.2s;
          ">⚡ Roll (${die.energyCost || 1}⚡)</button>
        ` : ''}

        ${die.isRolled ? `
          <button class="die-reroll-btn" data-die-id="${die.id}" style="
            padding: 10px 16px;
            background: ${combat.player.rerolls > 0 ? 'linear-gradient(145deg, #FF9800, #F57C00)' : 'rgba(100,100,100,0.5)'};
            border: 2px solid ${combat.player.rerolls > 0 ? '#FFB74D' : '#666'};
            border-radius: 8px;
            color: white;
            cursor: ${combat.player.rerolls > 0 ? 'pointer' : 'not-allowed'};
            font-weight: bold;
            font-size: 13px;
            text-transform: uppercase;
            box-shadow: ${combat.player.rerolls > 0 ? '0 2px 8px rgba(255,152,0,0.4)' : 'none'};
            transition: all 0.2s;
            ${combat.player.rerolls <= 0 ? 'opacity: 0.5;' : ''}
          ">🔄 Reroll</button>
          <button class="die-confirm-btn" data-die-id="${die.id}" style="
            padding: 10px 16px;
            background: linear-gradient(145deg, #4CAF50, #2E7D32);
            border: 2px solid #66BB6A;
            border-radius: 8px;
            color: white;
            cursor: pointer;
            font-weight: bold;
            font-size: 13px;
            text-transform: uppercase;
            box-shadow: 0 2px 8px rgba(76,175,80,0.4);
            transition: all 0.2s;
          ">✓ Confirm</button>
        ` : ''}

        ${die.isExhausted ? `
          <div style="
            padding: 8px 16px;
            background: rgba(244,67,54,0.2);
            border: 2px solid #F44336;
            border-radius: 8px;
            color: #F44336;
            font-weight: bold;
            font-size: 12px;
          ">EXHAUSTED</div>
        ` : ''}
      </div>
    </div>
  `;
}

/**
 * Render spellbook
 */
function renderSpellbook(combat) {
  if (!combat.spells || combat.spells.length === 0) {
    return `
      <div style="padding: 15px; text-align: center; color: #666;">
        <div style="font-size: 14px;">📖 Spellbook</div>
        <div style="font-size: 12px; margin-top: 5px;">No spells available</div>
      </div>
    `;
  }

  return `
    <div style="padding: 10px;">
      <div style="
        font-size: 14px;
        font-weight: bold;
        color: #9C27B0;
        margin-bottom: 10px;
        display: flex;
        align-items: center;
        gap: 8px;
      ">
        📖 Spellbook
      </div>
      <div style="display: flex; flex-wrap: wrap; gap: 8px;">
        ${combat.spells.map(spell => {
          const isUsable = canCastSpell(spell, combat);
          const cost = getSpellCost(spell, combat);

          return `
            <button class="spell-btn" data-spell-name="${spell.name}" style="
              padding: 8px 12px;
              background: ${isUsable ? 'linear-gradient(145deg, #9C27B0, #7B1FA2)' : 'rgba(0,0,0,0.3)'};
              border: 1px solid ${isUsable ? '#BA68C8' : '#333'};
              border-radius: 6px;
              color: ${isUsable ? 'white' : '#666'};
              cursor: ${isUsable ? 'pointer' : 'not-allowed'};
              font-size: 12px;
              ${!isUsable ? 'opacity: 0.6;' : ''}
            " title="${spell.description}">
              ${spell.name} (${cost}💎)
            </button>
          `;
        }).join('')}
      </div>
    </div>
  `;
}

/**
 * Check if spell can be cast
 */
function canCastSpell(spell, combat) {
  const cost = getSpellCost(spell, combat);
  if (combat.player.mana < cost) return false;
  if (spell.keywords.includes('SingleCast') && combat.usedSingleCast[spell.name]) return false;
  if (spell.keywords.includes('Cooldown') && combat.spellCooldowns[spell.name]) return false;
  return true;
}

/**
 * Get current spell cost
 */
function getSpellCost(spell, combat) {
  let cost = spell.cost;
  const castCount = combat.spellCasts[spell.name] || 0;

  if (spell.keywords.includes('Channel')) {
    cost = Math.max(1, cost - castCount);
  }
  if (spell.keywords.includes('Deplete')) {
    cost = cost + castCount;
  }

  return cost;
}

/**
 * Render combat log
 */
function renderCombatLog(combat) {
  const recentLogs = combat.log.slice(-10);

  return `
    <div style="display: flex; flex-direction: column; gap: 3px;">
      ${recentLogs.map(log => {
        const colors = {
          'info': '#aaa',
          'success': '#4CAF50',
          'warning': '#FFD700',
          'danger': '#F44336'
        };
        return `
          <div style="color: ${colors[log.type] || '#aaa'}; font-size: 11px;">
            ${log.message}
          </div>
        `;
      }).join('')}
    </div>
  `;
}

// Move type to emoji/symbol mapping for dice faces (avoids CORS issues with images)
const moveEmojis = {
  'dmg': '⚔',
  'block': '🛡',
  'heal': '❤',
  'mana': '◆',
  'reroll': '↻',
  'inflict': '☠',
  'get': '★',
  'cleanse': '✦',
  'spawn': '◎',
  'alter': '⟲',
  'pain': '✖'
};

/**
 * Create custom texture for combat D6 face with PNG images when available
 * @param {Object} face - Face object with effects array
 * @param {string} bgColor - Background color
 * @returns {HTMLCanvasElement} Canvas with rendered face
 */
function createCombatFaceTexture(face, bgColor = '#cc6600') {
  const canvas = document.createElement('canvas');
  canvas.width = 128;
  canvas.height = 128;
  const ctx = canvas.getContext('2d');

  // Background
  ctx.fillStyle = bgColor;
  ctx.fillRect(0, 0, 128, 128);

  // Border
  ctx.strokeStyle = '#000000';
  ctx.lineWidth = 4;
  ctx.strokeRect(2, 2, 124, 124);

  // Inner highlight
  ctx.strokeStyle = 'rgba(255,255,255,0.3)';
  ctx.lineWidth = 2;
  ctx.strokeRect(6, 6, 116, 116);

  // Handle blank face
  if (face.isBlank) {
    ctx.fillStyle = 'rgba(0,0,0,0.3)';
    ctx.fillRect(10, 10, 108, 108);
    ctx.fillStyle = '#666666';
    ctx.font = 'bold 48px Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('—', 64, 64);
    return canvas;
  }

  // Get the first effect for display
  const effect = face.effects && face.effects[0];
  if (!effect) {
    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 32px Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('?', 64, 64);
    return canvas;
  }

  // Draw the value number at top
  const value = effect.value || 0;
  ctx.fillStyle = '#ffffff';
  ctx.font = 'bold 52px Arial';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  ctx.strokeStyle = '#000000';
  ctx.lineWidth = 5;
  ctx.strokeText(value.toString(), 64, 5);
  ctx.fillText(value.toString(), 64, 5);

  // Try to draw move type image, fall back to emoji
  const moveKey = effect.move?.toLowerCase();
  const cachedImage = moveImageCache[moveKey];

  if (cachedImage && cachedImage.complete && cachedImage.naturalWidth > 0) {
    // Draw the PNG image
    try {
      const imgSize = 48;
      const imgX = 64 - imgSize / 2;
      const imgY = 68;
      ctx.drawImage(cachedImage, imgX, imgY, imgSize, imgSize);
    } catch (e) {
      // Fall back to emoji if image drawing fails
      drawMoveEmoji(ctx, moveKey, effect.move);
    }
  } else {
    // Fall back to emoji
    drawMoveEmoji(ctx, moveKey, effect.move);
  }

  // If there are multiple effects, add indicator
  if (face.effects && face.effects.length > 1) {
    ctx.fillStyle = '#FFD700';
    ctx.font = 'bold 18px Arial';
    ctx.textAlign = 'right';
    ctx.textBaseline = 'bottom';
    ctx.fillText('+', 118, 118);
  }

  return canvas;
}

/**
 * Draw move emoji on canvas (fallback when PNG not available)
 */
function drawMoveEmoji(ctx, moveKey, moveName) {
  const symbol = moveEmojis[moveKey];

  ctx.fillStyle = '#ffffff';
  ctx.textAlign = 'center';

  if (symbol) {
    ctx.font = '42px Arial';
    ctx.textBaseline = 'middle';
    ctx.strokeStyle = '#000000';
    ctx.lineWidth = 3;
    ctx.strokeText(symbol, 64, 90);
    ctx.fillText(symbol, 64, 90);
  } else {
    // Fallback: draw move name text
    const name = moveName || '?';
    ctx.font = 'bold 18px Arial';
    ctx.textBaseline = 'middle';
    ctx.strokeStyle = '#000000';
    ctx.lineWidth = 3;
    ctx.strokeText(name, 64, 90);
    ctx.fillText(name, 64, 90);
  }
}

/**
 * Extended DiceRenderer for combat dice with custom face textures
 */
class CombatDiceRenderer extends DiceRendererInstance {
  constructor() {
    super();
    this.faces = [];
    this.bgColor = '#cc6600';
    this.targetFaceIndex = null;
  }

  /**
   * Create a D6 mesh with image faces for combat
   */
  createCombatD6Mesh(faces, bgColor = '#cc6600') {
    this.bgColor = bgColor;
    this.faces = faces;

    // Create cube geometry
    const geometry = new THREE.BoxGeometry(2.0, 2.0, 2.0, 4, 4, 4);

    const materials = [];

    // Cube face order in Three.js BoxGeometry: +X, -X, +Y, -Y, +Z, -Z
    // We map our 6 dice faces to these positions
    this.faceNormals = [
      new THREE.Vector3(1, 0, 0),   // Face 0 -> +X (right)
      new THREE.Vector3(-1, 0, 0),  // Face 1 -> -X (left)
      new THREE.Vector3(0, 1, 0),   // Face 2 -> +Y (top)
      new THREE.Vector3(0, -1, 0),  // Face 3 -> -Y (bottom)
      new THREE.Vector3(0, 0, 1),   // Face 4 -> +Z (front)
      new THREE.Vector3(0, 0, -1)   // Face 5 -> -Z (back)
    ];

    // Map dice faces to cube faces
    for (let i = 0; i < 6; i++) {
      const face = faces[i] || { isBlank: true, effects: [], raw: '?' };
      const canvas = createCombatFaceTexture(face, bgColor);
      const texture = new THREE.CanvasTexture(canvas);
      texture.needsUpdate = true;

      const material = new THREE.MeshStandardMaterial({
        map: texture,
        roughness: 0.5,
        metalness: 0.1
      });

      materials.push(material);
    }

    const mesh = new THREE.Mesh(geometry, materials);
    return mesh;
  }

  /**
   * Create combat dice and add to scene
   */
  createCombatDice(faces, bgColor = '#cc6600') {
    if (this.mesh) {
      this.scene.remove(this.mesh);
      this.disposeMesh();
    }

    this.hasRolled = false;
    this.diceType = 'd6-combat';
    this.faces = faces;
    this.targetFaceIndex = null;

    this.mesh = this.createCombatD6Mesh(faces, bgColor);
    this.scene.add(this.mesh);
  }

  /**
   * Roll the dice to show a specific face
   * @param {number} faceIndex - 0-based index of face to show
   * @param {Function} callback - Called when animation completes
   */
  rollToFace(faceIndex, callback) {
    if (this.isRolling) {
      console.warn('Dice is already rolling');
      return;
    }

    this.isRolling = true;
    this.hasRolled = true;
    this.targetFaceIndex = faceIndex;

    const duration = 1200;
    const startTime = Date.now();

    // Store starting rotation
    const startQuat = new THREE.Quaternion().setFromEuler(this.mesh.rotation);

    // Calculate target rotation to show the specified face
    const targetRotation = this.calculateFaceRotation(faceIndex + 1);
    const targetEuler = new THREE.Euler(targetRotation.x, targetRotation.y, targetRotation.z, 'XYZ');
    const targetQuat = new THREE.Quaternion().setFromEuler(targetEuler);

    // Random spin axis for visual variety
    const spinAxis = new THREE.Vector3(
      Math.random() - 0.5,
      Math.random() - 0.5,
      Math.random() - 0.5
    ).normalize();
    const extraSpins = 2 + Math.random();

    const animateRoll = () => {
      const elapsed = Date.now() - startTime;
      const progress = Math.min(elapsed / duration, 1);

      if (progress < 1) {
        const easeProgress = 1 - Math.pow(1 - progress, 3);
        const currentQuat = new THREE.Quaternion();

        if (progress < 0.6) {
          // Spinning phase
          const spinAmount = extraSpins * Math.PI * 2 * progress / 0.6;
          const spinQuat = new THREE.Quaternion().setFromAxisAngle(spinAxis, spinAmount);
          currentQuat.multiplyQuaternions(spinQuat, startQuat);
        } else {
          // Transition to final position
          const blendProgress = (progress - 0.6) / 0.4;
          const blendEase = 1 - Math.pow(1 - blendProgress, 2);

          const spinAmount = extraSpins * Math.PI * 2;
          const spinQuat = new THREE.Quaternion().setFromAxisAngle(spinAxis, spinAmount);
          const finalSpinQuat = new THREE.Quaternion().multiplyQuaternions(spinQuat, startQuat);

          currentQuat.slerpQuaternions(finalSpinQuat, targetQuat, blendEase);
        }

        this.mesh.rotation.setFromQuaternion(currentQuat);
        requestAnimationFrame(animateRoll);
      } else {
        // Final position - ensure exact target
        this.mesh.rotation.set(targetRotation.x, targetRotation.y, targetRotation.z);
        this.isRolling = false;
        if (callback) callback();
      }
    };

    // Start with a small jump
    this.animateDiceJump(() => animateRoll());
  }

  /**
   * Calculate rotation to show a face toward camera
   */
  calculateFaceRotation(faceNumber) {
    const faceIndex = faceNumber - 1;

    if (faceIndex < 0 || faceIndex >= 6 || !this.faceNormals[faceIndex]) {
      return { x: 0, y: 0, z: 0 };
    }

    const normal = this.faceNormals[faceIndex].clone();
    const targetDirection = new THREE.Vector3(0, 0, 1); // Camera is at +Z

    const quaternion = new THREE.Quaternion();
    quaternion.setFromUnitVectors(normal, targetDirection);

    const euler = new THREE.Euler();
    euler.setFromQuaternion(quaternion, 'XYZ');

    return { x: euler.x, y: euler.y, z: euler.z };
  }

  /**
   * Animate dice jumping
   */
  animateDiceJump(callback) {
    const jumpHeight = 1.0;
    const jumpDuration = 200;
    const startY = this.mesh.position.y;
    const startTime = Date.now();

    const jump = () => {
      const elapsed = Date.now() - startTime;
      const progress = Math.min(elapsed / jumpDuration, 1);

      if (progress < 0.5) {
        this.mesh.position.y = startY + (jumpHeight * (progress * 2));
      } else {
        this.mesh.position.y = startY + (jumpHeight * (1 - (progress - 0.5) * 2));
      }

      if (progress < 1) {
        requestAnimationFrame(jump);
      } else {
        this.mesh.position.y = startY;
        callback();
      }
    };

    jump();
  }

  disposeMesh() {
    if (!this.mesh) return;

    if (this.mesh.geometry) this.mesh.geometry.dispose();
    if (this.mesh.material) {
      if (Array.isArray(this.mesh.material)) {
        this.mesh.material.forEach(mat => {
          if (mat.map) mat.map.dispose();
          mat.dispose();
        });
      } else {
        if (this.mesh.material.map) this.mesh.material.map.dispose();
        this.mesh.material.dispose();
      }
    }
  }
}

// Make CombatDiceRenderer available globally
if (typeof window !== 'undefined') {
  window.CombatDiceRenderer = CombatDiceRenderer;
}

/**
 * Initialize 3D dice renderers for all dice in combat
 */
function initialize3DDice(combat) {
  // Clean up old renderers first (but preserve rolled states)
  Object.keys(activeDiceRenderers).forEach(diceId => {
    const data = activeDiceRenderers[diceId];
    if (data && data.renderer) {
      // Save rolled state before cleanup
      if (data.renderer.hasRolled) {
        rolledDiceStates[diceId] = {
          hasRolled: true,
          faceIndex: data.renderer.targetFaceIndex,
          rotation: data.renderer.mesh ? {
            x: data.renderer.mesh.rotation.x,
            y: data.renderer.mesh.rotation.y,
            z: data.renderer.mesh.rotation.z
          } : null
        };
      }
      try {
        data.renderer.dispose();
      } catch (e) {
        console.warn('Error disposing dice renderer:', e);
      }
    }
  });
  activeDiceRenderers = {};

  combat.playerDice.forEach(die => {
    const container = document.getElementById(`dice-3d-${die.id}`);
    if (!container) return;

    // Determine source color
    const bgColor = die.source === 'character' ? '#cc6600' :
      die.source === 'weapon' ? '#666666' :
      die.source === 'ally' ? '#3366cc' : '#cc6600';

    try {
      // Create renderer instance
      const renderer = new CombatDiceRenderer();
      renderer.init(container);
      renderer.createCombatDice(die.faces, bgColor);

      // Restore rolled state if die was previously rolled
      const savedState = rolledDiceStates[die.id];
      if (die.isRolled && savedState) {
        renderer.hasRolled = true;
        renderer.targetFaceIndex = savedState.faceIndex;
        // Restore exact rotation to stop idle animation
        if (savedState.rotation && renderer.mesh) {
          renderer.mesh.rotation.set(savedState.rotation.x, savedState.rotation.y, savedState.rotation.z);
        }
      } else if (die.isRolled && die.currentFaceIndex !== undefined) {
        // Die was rolled but we don't have saved state - set to correct face
        renderer.hasRolled = true;
        const targetRotation = renderer.calculateFaceRotation(die.currentFaceIndex + 1);
        if (renderer.mesh) {
          renderer.mesh.rotation.set(targetRotation.x, targetRotation.y, targetRotation.z);
        }
      }

      // Clear saved state if die is no longer rolled (was reset)
      if (!die.isRolled) {
        delete rolledDiceStates[die.id];
      }

      // Store reference
      activeDiceRenderers[die.id] = {
        renderer: renderer,
        die: die
      };

      // Make container clickable for roll
      if (!die.isRolled && !die.isExhausted) {
        container.style.cursor = 'pointer';
        container.addEventListener('click', () => handleDiceContainerClick(die.id));
      }
    } catch (e) {
      console.error('Failed to initialize 3D dice for', die.id, e);
    }
  });
}

/**
 * Handle click on 3D dice container
 */
function handleDiceContainerClick(diceId) {
  const combat = window.CombatEngine.getCombatState();
  const die = combat?.playerDice.find(d => d.id === diceId);

  if (!die || die.isRolled || die.isExhausted) return;

  // Trigger roll via button click handler
  const rollBtn = document.querySelector(`.die-roll-btn[data-die-id="${diceId}"]`);
  if (rollBtn) {
    rollBtn.click();
  }
}

/**
 * Animate 3D dice roll to show specific face
 */
function animate3DDiceRoll(diceId, faceIndex, callback) {
  const rendererData = activeDiceRenderers[diceId];
  if (!rendererData || !rendererData.renderer) {
    if (callback) callback();
    return;
  }

  const renderer = rendererData.renderer;

  // Use our custom rollToFace method that ensures correct face is shown
  renderer.rollToFace(faceIndex, callback);
}

/**
 * Initialize 3D dice renderers for enemy intent dice
 * @param {Object} combat - Combat state
 * @param {boolean} shouldAnimate - Whether to animate the dice roll (only on turn start)
 */
function initializeEnemy3DDice(combat, shouldAnimate = true) {
  // Clean up old enemy renderers
  cleanupEnemy3DDice();

  if (!combat.enemies || combat.enemies.length === 0) {
    return;
  }

  combat.enemies.forEach(enemy => {
    if (enemy.health <= 0) return;

    // Check if enemy has intent
    if (!enemy.currentIntent || enemy.currentIntent.length === 0) {
      console.log(`Enemy ${enemy.name} has no intent`);
      return;
    }

    enemy.currentIntent.forEach((intent, dieIdx) => {
      const diceId = `enemy-${enemy.id}-${dieIdx}`;
      const container = document.getElementById(`enemy-dice-3d-${diceId}`);

      if (!container) {
        console.warn(`Container not found for enemy dice: enemy-dice-3d-${diceId}`);
        return;
      }

      // Enemy dice are red-tinted
      const bgColor = '#993333';

      try {
        // Create renderer instance
        const renderer = new CombatDiceRenderer();
        renderer.init(container);

        // Create dice with faces from intent
        const faces = [];
        // Build 6 faces - use enemy dice if available, otherwise create from intent
        if (enemy.dice && enemy.dice.length >= 6) {
          for (let i = 0; i < 6; i++) {
            faces.push(enemy.dice[i] || { isBlank: true });
          }
        } else {
          // Use intent face repeated for all 6 sides as fallback
          const intentFace = intent.face || { isBlank: true };
          for (let i = 0; i < 6; i++) {
            faces.push(intentFace);
          }
        }

        renderer.createCombatDice(faces, bgColor);

        // Store reference
        enemyDiceRenderers[diceId] = {
          renderer: renderer,
          enemyId: enemy.id,
          faceIndex: intent.faceIndex || 0
        };

        // Set to the intent face - animate only on turn start
        const targetFace = intent.faceIndex !== undefined ? intent.faceIndex : 0;
        if (shouldAnimate) {
          setTimeout(() => {
            animateEnemyDiceRoll(diceId, targetFace);
          }, 100 + (dieIdx * 200)); // Stagger the rolls
        } else {
          // Just set the face without animation
          renderer.hasRolled = true;
          const targetRotation = renderer.calculateFaceRotation(targetFace + 1);
          if (renderer.mesh) {
            renderer.mesh.rotation.set(targetRotation.x, targetRotation.y, targetRotation.z);
          }
        }

      } catch (e) {
        console.error('Failed to initialize enemy 3D dice for', diceId, e);
      }
    });
  });
}

/**
 * Animate enemy dice roll to show intent face
 */
function animateEnemyDiceRoll(diceId, faceIndex) {
  const rendererData = enemyDiceRenderers[diceId];
  if (!rendererData || !rendererData.renderer) return;

  const renderer = rendererData.renderer;
  renderer.rollToFace(faceIndex, null);
}

/**
 * Clean up all enemy 3D dice renderers
 */
function cleanupEnemy3DDice() {
  Object.keys(enemyDiceRenderers).forEach(diceId => {
    const data = enemyDiceRenderers[diceId];
    if (data && data.renderer) {
      try {
        data.renderer.dispose();
      } catch (e) {
        console.warn('Error disposing enemy dice renderer:', e);
      }
    }
  });
  enemyDiceRenderers = {};
}

/**
 * Clean up all 3D dice renderers (player and enemy)
 */
function cleanup3DDice() {
  // Clean up player dice
  Object.keys(activeDiceRenderers).forEach(diceId => {
    const data = activeDiceRenderers[diceId];
    if (data && data.renderer) {
      try {
        data.renderer.dispose();
      } catch (e) {
        console.warn('Error disposing dice renderer:', e);
      }
    }
  });
  activeDiceRenderers = {};

  // Clean up enemy dice
  cleanupEnemy3DDice();
}

/**
 * Attach event listeners to combat UI
 */
function attachCombatEventListeners(combat) {
  // Preload images then initialize 3D dice after DOM is ready
  preloadMoveImages().then(() => {
    setTimeout(() => {
      initialize3DDice(combat);
      // Always try to initialize enemy dice - the function will check if renderers already exist
      // Only animate the roll on turn change
      const shouldAnimate = lastEnemyDiceInitTurn !== combat.turn;
      if (shouldAnimate) {
        lastEnemyDiceInitTurn = combat.turn;
      }
      initializeEnemy3DDice(combat, shouldAnimate);
    }, 50);
  });

  // Roll buttons
  document.querySelectorAll('.die-roll-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const diceId = e.target.dataset.dieId;
      const result = window.CombatEngine.rollPlayerDie(diceId);
      if (result.success) {
        // Animate the 3D dice roll
        const faceIndex = result.faceIndex !== undefined ? result.faceIndex : 0;
        animate3DDiceRoll(diceId, faceIndex, () => {
          updateCombatDisplay();
        });
      } else {
        alert(result.error);
      }
    });
  });

  // Confirm buttons
  document.querySelectorAll('.die-confirm-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const diceId = e.target.dataset.dieId;
      const combatData = window.CombatEngine.getCombatState();

      // Find the die and check if it needs a target
      const die = combatData?.playerDice.find(d => d.id === diceId);
      if (!die || !die.currentFace) return;

      // Check if face has damage or other targeting effects
      const needsTarget = !die.currentFace.isBlank && die.currentFace.effects.some(effect => {
        const move = effect.move?.toLowerCase();
        return ['dmg', 'inflict', 'assassinate'].includes(move);
      });

      // Build targets based on current selection and combat state
      const targets = { self: true };

      // Add enemy targeting
      if (combatData && combatData.enemies) {
        const aliveEnemies = combatData.enemies.filter(en => en.health > 0);

        // If only one enemy, auto-target it
        if (aliveEnemies.length === 1) {
          targets.enemyId = aliveEnemies[0].id;
        } else if (aliveEnemies.length > 1 && window.selectedEnemyTarget) {
          // Use selected target if available
          targets.enemyId = window.selectedEnemyTarget;
        } else if (aliveEnemies.length > 1 && needsTarget) {
          // Force target selection for damage effects
          showTargetRequiredMessage();
          highlightEnemiesForSelection();
          return; // Don't confirm until target is selected
        } else if (aliveEnemies.length > 1) {
          // Default to first enemy for non-targeting effects
          targets.enemyId = aliveEnemies[0].id;
        }
      }

      const result = window.CombatEngine.confirmDie(diceId, targets);
      if (result.success) {
        window.selectedEnemyTarget = null; // Clear selection after use
        updateCombatDisplay();
        checkCombatEnd();
      }
    });
  });

  // Reroll buttons
  document.querySelectorAll('.die-reroll-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const diceId = e.target.dataset.dieId;
      const combatData = window.CombatEngine.getCombatState();

      // Check if player has rerolls
      if (!combatData || combatData.player.rerolls < 1) {
        showTargetRequiredMessage();
        const msg = document.getElementById('target-required-msg');
        if (msg) msg.innerHTML = '🔄 No rerolls available!';
        return;
      }

      const result = window.CombatEngine.rerollPlayerDie(diceId);
      if (result.success) {
        // Animate the 3D dice reroll
        const faceIndex = result.faceIndex !== undefined ? result.faceIndex : 0;
        animate3DDiceRoll(diceId, faceIndex, () => {
          updateCombatDisplay();
        });
      } else {
        alert(result.error);
      }
    });
  });

  // Spell buttons
  document.querySelectorAll('.spell-btn').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const spellName = e.target.dataset.spellName;

      // Build targets for spells
      const targets = { self: true };
      const combatData = window.CombatEngine.getCombatState();
      if (combatData && combatData.enemies) {
        const aliveEnemies = combatData.enemies.filter(en => en.health > 0);
        if (aliveEnemies.length === 1) {
          targets.enemyId = aliveEnemies[0].id;
        } else if (aliveEnemies.length > 1 && window.selectedEnemyTarget) {
          targets.enemyId = window.selectedEnemyTarget;
        } else if (aliveEnemies.length > 1) {
          targets.enemyId = aliveEnemies[0].id;
        }
      }

      const result = window.CombatEngine.castSpell(spellName, targets);
      if (result.success) {
        window.selectedEnemyTarget = null;
        updateCombatDisplay();
        checkCombatEnd();
      } else {
        alert(result.error);
      }
    });
  });

  // End turn button
  const endTurnBtn = document.getElementById('combat-end-turn-btn');
  if (endTurnBtn) {
    endTurnBtn.addEventListener('click', () => {
      const result = window.CombatEngine.endTurn();
      if (result.success) {
        updateCombatDisplay();
        checkCombatEnd();
      }
    });
  }

  // Dash button
  const dashBtn = document.getElementById('combat-dash-btn');
  if (dashBtn) {
    dashBtn.addEventListener('click', () => {
      const result = window.CombatEngine.useDash();
      if (result.success) {
        updateCombatDisplay();
      } else {
        alert(result.error);
      }
    });
  }

  // Enemy targeting (click to select)
  document.querySelectorAll('.enemy-card').forEach(card => {
    card.addEventListener('click', (e) => {
      const enemyId = card.dataset.enemyId;
      // Store selected target for next action
      window.selectedEnemyTarget = enemyId;
      // Visual feedback
      document.querySelectorAll('.enemy-card').forEach(c => {
        c.style.boxShadow = '';
      });
      card.style.boxShadow = '0 0 10px #FFD700';
    });
  });
}

/**
 * Show message requiring target selection
 */
function showTargetRequiredMessage() {
  // Create a floating message
  const existingMsg = document.getElementById('target-required-msg');
  if (existingMsg) existingMsg.remove();

  const msg = document.createElement('div');
  msg.id = 'target-required-msg';
  msg.innerHTML = '⚔️ Select a target first!';
  msg.style.cssText = `
    position: fixed;
    top: 20%;
    left: 50%;
    transform: translateX(-50%);
    background: rgba(244, 67, 54, 0.95);
    color: white;
    padding: 12px 24px;
    border-radius: 8px;
    font-size: 16px;
    font-weight: bold;
    z-index: 1000;
    box-shadow: 0 4px 12px rgba(0,0,0,0.4);
    animation: fadeInOut 2s forwards;
  `;

  // Add animation style if not exists
  if (!document.getElementById('target-msg-style')) {
    const style = document.createElement('style');
    style.id = 'target-msg-style';
    style.textContent = `
      @keyframes fadeInOut {
        0% { opacity: 0; transform: translateX(-50%) translateY(-10px); }
        15% { opacity: 1; transform: translateX(-50%) translateY(0); }
        85% { opacity: 1; }
        100% { opacity: 0; }
      }
    `;
    document.head.appendChild(style);
  }

  document.body.appendChild(msg);

  // Remove after animation
  setTimeout(() => msg.remove(), 2000);
}

/**
 * Highlight enemies to indicate target selection is needed
 */
function highlightEnemiesForSelection() {
  document.querySelectorAll('.enemy-card').forEach(card => {
    const enemyId = card.dataset.enemyId;
    const combat = window.CombatEngine.getCombatState();
    const enemy = combat?.enemies.find(e => e.id === enemyId);

    if (enemy && enemy.health > 0) {
      // Add pulsing highlight effect
      card.style.animation = 'targetPulse 0.6s ease-in-out 3';
      card.style.boxShadow = '0 0 20px rgba(255, 215, 0, 0.8)';

      // Remove effect after animation
      setTimeout(() => {
        card.style.animation = '';
        if (!window.selectedEnemyTarget || window.selectedEnemyTarget !== enemyId) {
          card.style.boxShadow = '';
        }
      }, 1800);
    }
  });

  // Add pulse animation if not exists
  if (!document.getElementById('target-pulse-style')) {
    const style = document.createElement('style');
    style.id = 'target-pulse-style';
    style.textContent = `
      @keyframes targetPulse {
        0%, 100% { box-shadow: 0 0 10px rgba(255, 215, 0, 0.4); }
        50% { box-shadow: 0 0 25px rgba(255, 215, 0, 0.9); }
      }
    `;
    document.head.appendChild(style);
  }
}

/**
 * Update combat display
 */
function updateCombatDisplay() {
  const combat = window.CombatEngine.getCombatState();
  const container = document.getElementById('new-combat-container')?.parentElement ||
                   document.getElementById('combat-modal-content');
  if (combat && container) {
    renderCombatUI(combat, container);
  }
}

/**
 * Check if combat has ended
 */
function checkCombatEnd() {
  const combat = window.CombatEngine.getCombatState();
  if (!combat) return;

  if (combat.phase === 'victory') {
    setTimeout(() => {
      alert('Victory!');
      window.CombatEngine.endCombat(true);
      // TODO: Handle victory rewards
    }, 500);
  } else if (combat.phase === 'defeat') {
    setTimeout(() => {
      alert('Defeat!');
      window.CombatEngine.endCombat(false);
      // TODO: Handle defeat consequences
    }, 500);
  }
}

// Export to global scope
if (typeof window !== 'undefined') {
  window.CombatUI = {
    renderCombatUI,
    updateCombatDisplay,
    checkCombatEnd,
    cleanup3DDice,
    initialize3DDice,
    animate3DDiceRoll,
    initializeEnemy3DDice,
    animateEnemyDiceRoll,
    preloadMoveImages
  };
}
