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

/**
 * Render the new combat UI
 * @param {Object} combat - Combat state from CombatEngine
 * @param {HTMLElement} container - Container element
 */
function renderCombatUI(combat, container) {
  if (!combat) return;

  const html = `
    <div id="new-combat-container" style="
      display: flex;
      flex-direction: column;
      width: 100%;
      height: 100%;
      background: linear-gradient(135deg, #1a1410 0%, #2a1810 100%);
      padding: 15px;
      gap: 10px;
      overflow: hidden;
    ">
      <!-- Top: Resources Bar -->
      ${renderResourcesBar(combat)}

      <!-- Middle: Combat Area -->
      <div style="
        flex: 1;
        display: flex;
        gap: 15px;
        min-height: 0;
        overflow: hidden;
      ">
        <!-- Left: Player Side -->
        <div style="flex: 1; display: flex; flex-direction: column; gap: 10px;">
          ${renderPlayerSection(combat)}
          ${renderAlliesSection(combat)}
        </div>

        <!-- Center: VS and Actions -->
        <div style="
          width: 120px;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 15px;
        ">
          <div style="
            font-size: 32px;
            font-weight: bold;
            color: #ff6644;
            text-shadow: 0 0 10px rgba(255,100,50,0.5);
          ">VS</div>
          <button id="combat-end-turn-btn" style="
            padding: 12px 20px;
            font-size: 16px;
            font-weight: bold;
            background: linear-gradient(145deg, #4CAF50, #2E7D32);
            border: 2px solid #66BB6A;
            border-radius: 8px;
            color: white;
            cursor: pointer;
            text-transform: uppercase;
          ">End Turn</button>
          <button id="combat-dash-btn" style="
            padding: 8px 16px;
            font-size: 14px;
            background: linear-gradient(145deg, #2196F3, #1565C0);
            border: 2px solid #42A5F5;
            border-radius: 6px;
            color: white;
            cursor: pointer;
            ${combat.player.dash > 0 ? '' : 'opacity: 0.5; cursor: not-allowed;'}
          ">Dash (${combat.player.dash})</button>
        </div>

        <!-- Right: Enemy Side -->
        <div style="flex: 1; display: flex; flex-direction: column; gap: 10px; overflow-y: auto;">
          ${renderEnemiesSection(combat)}
        </div>
      </div>

      <!-- Bottom: Dice Area -->
      <div style="
        background: rgba(0,0,0,0.4);
        border: 2px solid #444;
        border-radius: 10px;
        padding: 15px;
      ">
        ${renderDiceArea(combat)}
      </div>

      <!-- Spellbook (collapsible) -->
      <div id="spellbook-container" style="
        background: rgba(0,0,0,0.4);
        border: 2px solid #9C27B0;
        border-radius: 10px;
        max-height: 200px;
        overflow-y: auto;
      ">
        ${renderSpellbook(combat)}
      </div>

      <!-- Combat Log -->
      <div id="combat-log-container" style="
        background: rgba(0,0,0,0.3);
        border: 1px solid #333;
        border-radius: 6px;
        padding: 8px;
        max-height: 100px;
        overflow-y: auto;
        font-size: 12px;
      ">
        ${renderCombatLog(combat)}
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
 * Render player section
 */
function renderPlayerSection(combat) {
  const p = combat.player;

  return `
    <div style="
      background: rgba(76,175,80,0.1);
      border: 2px solid rgba(76,175,80,0.4);
      border-radius: 10px;
      padding: 15px;
      text-align: center;
    ">
      <div style="font-size: 18px; font-weight: bold; color: #4CAF50; margin-bottom: 10px;">
        YOU
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
 * Render single enemy card with image
 */
function renderEnemyCard(enemy, combat) {
  const isDead = enemy.health <= 0;
  // Get enemy image path - prefer imageUrl from data, fallback to getEnemyImagePath
  const enemyImagePath = enemy.imageUrl
    ? enemy.imageUrl
    : (typeof getEnemyImagePath === 'function'
      ? getEnemyImagePath(enemy.name)
      : `images/enemies/${enemy.name.replace(/\s+/g, '')}.png`);

  return `
    <div class="enemy-card" data-enemy-id="${enemy.id}" style="
      background: ${isDead ? 'rgba(0,0,0,0.3)' : 'rgba(244,67,54,0.1)'};
      border: 2px solid ${isDead ? '#333' : 'rgba(244,67,54,0.4)'};
      border-radius: 10px;
      padding: 12px;
      ${isDead ? 'opacity: 0.5;' : 'cursor: pointer;'}
      transition: all 0.2s;
    ">
      <div style="display: flex; gap: 12px; align-items: flex-start;">
        <!-- Enemy Image -->
        <div style="flex-shrink: 0;">
          <img src="${enemyImagePath}"
            alt="${enemy.name}"
            onerror="this.style.display='none'"
            style="
              width: 80px;
              height: 80px;
              object-fit: contain;
              image-rendering: pixelated;
              border-radius: 6px;
              background: rgba(0,0,0,0.3);
            "
          />
        </div>

        <!-- Enemy Info -->
        <div style="flex: 1; min-width: 0;">
          <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px;">
            <div style="font-size: 16px; font-weight: bold; color: ${isDead ? '#666' : '#F44336'};">
              ${enemy.name}
            </div>
            <div style="color: ${isDead ? '#666' : '#F44336'}; font-size: 14px;">
              ❤️ ${enemy.health}/${enemy.maxHealth}
            </div>
          </div>

          ${enemy.block > 0 ? `
            <div style="color: #78909C; font-size: 14px; margin-bottom: 5px;">
              🛡️ Block: ${enemy.block}
            </div>
          ` : ''}

          ${renderStatusEffects(enemy.statuses, enemy.id)}
        </div>
      </div>

      ${!isDead && enemy.currentIntent ? `
        <div style="
          margin-top: 10px;
          padding: 8px;
          background: rgba(255,200,0,0.1);
          border: 1px solid rgba(255,200,0,0.3);
          border-radius: 6px;
        ">
          <div style="font-size: 11px; color: #FFD700; text-transform: uppercase; margin-bottom: 4px;">
            Intent
          </div>
          <div style="font-size: 14px; color: #fff;">
            ${enemy.currentIntent.map(i => i.face.raw || 'Nothing').join(', ')}
          </div>
        </div>
      ` : ''}
    </div>
  `;
}

/**
 * Render status effects for a target
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

  const entries = Object.entries(statuses).filter(([k, v]) => v > 0);
  if (entries.length === 0) return '';

  return `
    <div style="display: flex; flex-wrap: wrap; gap: 4px; margin-top: 5px;">
      ${entries.map(([status, stacks]) => `
        <div title="${status}: ${stacks}" style="
          background: rgba(0,0,0,0.4);
          border-radius: 4px;
          padding: 2px 6px;
          font-size: 12px;
          display: flex;
          align-items: center;
          gap: 3px;
        ">
          <span>${statusIcons[status] || '❔'}</span>
          <span style="color: #fff;">${stacks}</span>
        </div>
      `).join('')}
    </div>
  `;
}

/**
 * Render dice area
 */
function renderDiceArea(combat) {
  return `
    <div style="
      display: flex;
      flex-wrap: wrap;
      gap: 15px;
      justify-content: center;
    ">
      ${combat.playerDice.map(die => renderDie(die, combat)).join('')}
    </div>
  `;
}

/**
 * Render a single die with 3D container
 */
function renderDie(die, combat) {
  const isAvailable = !die.isExhausted &&
    (die.source !== 'ally' || combat.allies.find(a => a.id === die.id)?.isAlive);

  const faceDisplay = die.isRolled && die.currentFace
    ? (die.currentFace.isBlank ? 'Blank' : die.currentFace.raw)
    : '?';

  const borderColor = die.isConfirmed ? '#4CAF50' :
    die.isRolled ? '#FFD700' :
    isAvailable ? '#2196F3' : '#666';

  // Determine source color for 3D die based on source type
  const sourceColor = die.source === 'character' ? '#cc6600' :
    die.source === 'weapon' ? '#888888' :
    die.source === 'ally' ? '#66ccff' : '#cc6600';

  return `
    <div class="combat-die" data-die-id="${die.id}" data-die-source="${die.source}" style="
      background: rgba(0,0,0,0.5);
      border: 3px solid ${borderColor};
      border-radius: 12px;
      padding: 15px;
      min-width: 160px;
      text-align: center;
      ${!isAvailable ? 'opacity: 0.5;' : ''}
    ">
      <div style="font-size: 12px; color: #888; text-transform: uppercase; margin-bottom: 5px;">
        ${die.source}
      </div>
      <div style="font-size: 14px; font-weight: bold; color: #fff; margin-bottom: 10px;">
        ${die.name}
      </div>

      <!-- 3D Dice Container -->
      <div id="dice-3d-${die.id}" class="dice-3d-container" data-die-id="${die.id}"
        data-source-color="${sourceColor}"
        style="
          width: 120px;
          height: 120px;
          margin: 0 auto 10px auto;
          background: #1a1410;
          border-radius: 8px;
          cursor: ${!die.isRolled && isAvailable ? 'pointer' : 'default'};
          position: relative;
        ">
        <!-- 3D renderer will be initialized here -->
        ${!die.isRolled && !activeDiceRenderers[die.id] ? `
          <div style="
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            color: #666;
            font-size: 14px;
            pointer-events: none;
          ">Click to Roll</div>
        ` : ''}
      </div>

      <!-- Result display (shown after roll) -->
      ${die.isRolled && die.currentFace ? `
        <div style="
          background: rgba(0,0,0,0.4);
          border-radius: 6px;
          padding: 8px;
          margin-bottom: 10px;
          font-size: 14px;
          color: #fff;
        ">
          ${die.currentFace.isBlank ? 'Blank' : die.currentFace.raw}
        </div>
      ` : ''}

      <div style="display: flex; gap: 8px; justify-content: center; flex-wrap: wrap;">
        ${!die.isRolled && isAvailable ? `
          <button class="die-roll-btn" data-die-id="${die.id}" style="
            padding: 8px 16px;
            background: linear-gradient(145deg, #2196F3, #1565C0);
            border: none;
            border-radius: 6px;
            color: white;
            cursor: pointer;
            font-weight: bold;
          ">Roll (1⚡)</button>
        ` : ''}

        ${die.isRolled && !die.isConfirmed ? `
          <button class="die-confirm-btn" data-die-id="${die.id}" style="
            padding: 8px 12px;
            background: linear-gradient(145deg, #4CAF50, #2E7D32);
            border: none;
            border-radius: 6px;
            color: white;
            cursor: pointer;
            font-weight: bold;
          ">Confirm</button>
          ${combat.player.rerolls > 0 ? `
            <button class="die-reroll-btn" data-die-id="${die.id}" style="
              padding: 8px 12px;
              background: linear-gradient(145deg, #FF9800, #F57C00);
              border: none;
              border-radius: 6px;
              color: white;
              cursor: pointer;
              font-weight: bold;
            ">Reroll</button>
          ` : ''}
        ` : ''}

        ${die.isConfirmed ? `
          <span style="color: #4CAF50; font-weight: bold;">✓ Used</span>
        ` : ''}

        ${die.isExhausted ? `
          <span style="color: #F44336; font-size: 12px;">Exhausted</span>
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

/**
 * Create custom face texture for combat dice
 * @param {string} text - Text to display on face (e.g., "2 Dmg", "3 Block")
 * @param {string} bgColor - Background color
 * @returns {Object} Dice side data for DiceRendererInstance
 */
function createCombatDiceSide(text, bgColor = '#cc6600') {
  return {
    value: 1,
    displayValue: null,
    displayText: text || '?'
  };
}

/**
 * Convert combat dice faces to DiceRenderer format
 * @param {Array} faces - Array of face objects from character/weapon/ally data
 * @param {string} sourceColor - Background color based on source type
 * @returns {Object} Dice data compatible with DiceRendererInstance
 */
function convertToDiceRendererFormat(faces, sourceColor = '#cc6600') {
  const sides = faces.map((face, index) => ({
    value: index + 1,
    displayValue: null,
    displayText: face.isBlank ? '—' : (face.raw || '?')
  }));

  return {
    type: 'd6-combat',
    sides: sides,
    sourceColor: sourceColor
  };
}

/**
 * Create custom texture for combat D6 face
 */
function createCombatFaceTexture(text, bgColor = '#cc6600') {
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

  // Text - handle multi-word text
  ctx.fillStyle = '#ffffff';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';

  // Adjust font size based on text length
  const fontSize = text.length > 8 ? 24 : text.length > 5 ? 32 : 40;
  ctx.font = `bold ${fontSize}px Arial`;

  // Add text outline for better readability
  ctx.strokeStyle = '#000000';
  ctx.lineWidth = 4;
  ctx.strokeText(text, 64, 64);
  ctx.fillText(text, 64, 64);

  return canvas;
}

/**
 * Extended DiceRenderer for combat dice with custom face textures
 */
class CombatDiceRenderer extends DiceRendererInstance {
  constructor() {
    super();
    this.faceTexts = [];
    this.bgColor = '#cc6600';
  }

  /**
   * Create a D6 mesh with custom text faces for combat
   */
  createCombatD6Mesh(faces, bgColor = '#cc6600') {
    this.bgColor = bgColor;
    this.faceTexts = faces.map(f => f.isBlank ? '—' : (f.raw || '?'));

    // Create cube geometry
    const geometry = new THREE.BoxGeometry(2.0, 2.0, 2.0, 4, 4, 4);

    const materials = [];

    // Cube face normals in order: right, left, top, bottom, front, back
    const cubeNormals = [
      new THREE.Vector3(1, 0, 0),
      new THREE.Vector3(-1, 0, 0),
      new THREE.Vector3(0, 1, 0),
      new THREE.Vector3(0, -1, 0),
      new THREE.Vector3(0, 0, 1),
      new THREE.Vector3(0, 0, -1)
    ];

    this.faceNormals = [];

    // Map dice faces to cube faces (indices 0-5)
    for (let i = 0; i < 6; i++) {
      const faceText = this.faceTexts[i] || '?';
      const canvas = createCombatFaceTexture(faceText, bgColor);
      const texture = new THREE.CanvasTexture(canvas);
      texture.needsUpdate = true;

      const material = new THREE.MeshStandardMaterial({
        map: texture,
        roughness: 0.5,
        metalness: 0.1
      });

      materials.push(material);
      this.faceNormals.push(cubeNormals[i].clone());
    }

    const mesh = new THREE.Mesh(geometry, materials);
    return mesh;
  }

  /**
   * Create combat dice and add to scene
   */
  createCombatDice(faces, bgColor = '#cc6600') {
    // Remove old dice if it exists
    if (this.mesh) {
      this.scene.remove(this.mesh);
      this.disposeMesh();
    }

    // Reset roll state
    this.hasRolled = false;
    this.diceType = 'd6-combat';

    // Create new mesh
    this.mesh = this.createCombatD6Mesh(faces, bgColor);
    this.scene.add(this.mesh);
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

  /**
   * Override calculateFaceRotation for D6
   */
  calculateFaceRotation(faceNumber) {
    const faceIndex = faceNumber - 1;

    if (faceIndex < 0 || faceIndex >= 6 || !this.faceNormals[faceIndex]) {
      console.warn('Invalid face number:', faceNumber);
      return { x: 0, y: 0, z: 0 };
    }

    const normal = this.faceNormals[faceIndex];
    const targetDirection = new THREE.Vector3(0, 0, 1);

    const quaternion = new THREE.Quaternion();
    quaternion.setFromUnitVectors(normal, targetDirection);

    const euler = new THREE.Euler();
    euler.setFromQuaternion(quaternion, 'XYZ');

    return { x: euler.x, y: euler.y, z: euler.z };
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
  // Clean up old renderers first
  cleanup3DDice();

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
 * Animate 3D dice roll
 */
function animate3DDiceRoll(diceId, faceIndex, callback) {
  const rendererData = activeDiceRenderers[diceId];
  if (!rendererData || !rendererData.renderer) {
    if (callback) callback();
    return;
  }

  const renderer = rendererData.renderer;
  const die = rendererData.die;

  // faceIndex is 0-based, rollDice expects 1-based
  const faceNumber = faceIndex + 1;

  // Create mock dice data for rollDice method
  const diceData = {
    type: 'd6-combat',
    sides: die.faces.map((f, i) => ({
      value: i + 1,
      displayValue: null,
      displayText: f.isBlank ? '—' : (f.raw || '?')
    }))
  };

  renderer.rollDice(diceData, faceNumber, callback);
}

/**
 * Clean up all 3D dice renderers
 */
function cleanup3DDice() {
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
}

/**
 * Attach event listeners to combat UI
 */
function attachCombatEventListeners(combat) {
  // Initialize 3D dice after DOM is ready
  setTimeout(() => {
    initialize3DDice(combat);
  }, 50);

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

      // Build targets based on current selection and combat state
      const targets = { self: true };

      // Add enemy targeting
      const combatData = window.CombatEngine.getCombatState();
      if (combatData && combatData.enemies) {
        const aliveEnemies = combatData.enemies.filter(en => en.health > 0);

        // If only one enemy, auto-target it
        if (aliveEnemies.length === 1) {
          targets.enemyId = aliveEnemies[0].id;
        } else if (aliveEnemies.length > 1 && window.selectedEnemyTarget) {
          // Use selected target if available
          targets.enemyId = window.selectedEnemyTarget;
        } else if (aliveEnemies.length > 1) {
          // Default to first enemy if no selection
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
    animate3DDiceRoll
  };
}
