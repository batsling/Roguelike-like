/**
 * Combat Engine - New Dice-Based Combat System
 * Handles the Slice & Dice inspired combat with:
 * - Character/Weapon/Ally dice pools
 * - Moves (Dmg, Block, Heal, etc.) with stat scaling
 * - Addons (Cantrip, Cleave, Wide, etc.)
 * - Status effects (Burn, Poison, Dodge, etc.)
 * - Spell system with keywords
 * - Energy and Mana resources
 */

// ============== COMBAT STATE ==============

var combatState = null;

/**
 * Initialize a new combat encounter
 * @param {Array} enemies - Array of enemy data from ENEMIES_DATA
 * @param {Object} characterData - Character data including dice
 * @param {Object} weaponData - Equipped weapon data (optional)
 * @param {Array} allies - Array of ally data (optional)
 * @returns {Object} Combat state
 */
function initCombat(enemies, characterData, weaponData = null, allies = []) {
  // Get player stats
  const playerStats = {
    strength: typeof getEffectiveStat === 'function' ? getEffectiveStat('strength') : (window.strength || 0),
    dexterity: typeof getEffectiveStat === 'function' ? getEffectiveStat('dexterity') : (window.dexterity || 0),
    intelligence: typeof getEffectiveStat === 'function' ? getEffectiveStat('intelligence') : (window.intelligence || 0),
    charisma: typeof getEffectiveStat === 'function' ? getEffectiveStat('charisma') : (window.charisma || 0)
  };

  // Calculate stat bonuses (every 3 = +1)
  const statBonuses = {
    strength: Math.floor(playerStats.strength / 3),
    dexterity: Math.floor(playerStats.dexterity / 3),
    intelligence: Math.floor(playerStats.intelligence / 3),
    charisma: Math.floor(playerStats.charisma / 3)
  };

  // Create player state - ensure health values are valid numbers
  const playerHealth = (typeof window.health === 'number' && !isNaN(window.health)) ? window.health : 10;
  const playerMaxHealth = (typeof window.maxHealth === 'number' && !isNaN(window.maxHealth)) ? window.maxHealth : 10;

  const player = {
    health: playerHealth,
    maxHealth: playerMaxHealth,
    energy: characterData.energy || 2,
    maxEnergy: characterData.energy || 2,
    mana: 0,
    maxMana: characterData.mana || 0,
    stats: playerStats,
    bonuses: statBonuses,
    block: 0,
    statuses: {},
    rerolls: window.reroll || 0,
    dash: window.dash || 0
  };

  // Create dice pool for player
  const playerDice = [];

  // Add character die
  if (characterData.dice) {
    playerDice.push({
      id: 'character',
      name: characterData.name,
      source: 'character',
      faces: characterData.dice,
      currentFace: null,
      isRolled: false,
      isConfirmed: false,
      isExhausted: false,
      energyCost: 1
    });
  }

  // Add weapon die if equipped
  if (weaponData && weaponData.dice) {
    playerDice.push({
      id: 'weapon',
      name: weaponData.name,
      source: 'weapon',
      faces: weaponData.dice,
      currentFace: null,
      isRolled: false,
      isConfirmed: false,
      isExhausted: false,
      energyCost: 1,
      tags: weaponData.tags || []
    });
  }

  // Add ally dice
  allies.forEach((ally, index) => {
    if (ally.dice) {
      playerDice.push({
        id: `ally_${index}`,
        name: ally.name,
        source: 'ally',
        allyData: ally,
        faces: ally.dice,
        currentFace: null,
        isRolled: false,
        isConfirmed: false,
        isExhausted: false,
        energyCost: 1
      });
    }
  });

  // Create enemy states
  const enemyStates = enemies.map((enemy, index) => {
    // Parse starting abilities from enemy.ability
    const startingStatuses = parseStartingAbilities(enemy.ability);

    return {
      id: `enemy_${index}`,
      name: enemy.name,
      type: enemy.type,
      difficulty: enemy.difficulty,
      health: enemy.hp,
      maxHealth: enemy.hp,
      block: 0,
      statuses: startingStatuses,
      ability: enemy.ability,
      game: enemy.game,
      location: enemy.location,
      dice: enemy.dice,
      currentIntent: null,
      imageUrl: enemy.imageUrl,
      position: index  // Position for Cleave targeting
    };
  });

  // Create ally states (for HP tracking)
  const allyStates = allies.map((ally, index) => ({
    id: `ally_${index}`,
    name: ally.name,
    health: ally.hp,
    maxHealth: ally.hp,
    block: 0,
    statuses: {},
    ability: ally.ability,
    isAlive: true,
    position: index,
    imageUrl: ally.imageUrl
  }));

  // Initialize combat state
  combatState = {
    player: player,
    enemies: enemyStates,
    allies: allyStates,
    playerDice: playerDice,
    turn: 1,
    phase: 'enemy_intent', // 'enemy_intent', 'player_status', 'player_action', 'end_turn', 'victory', 'defeat'
    log: [],
    spells: [], // Player's available spells
    spellCooldowns: {}, // Track spell cooldowns
    spellCasts: {}, // Track how many times each spell was cast (for Channel/Deplete)
    usedSingleCast: {}, // Track SingleCast spells used this combat
    pendingEffects: [], // Effects waiting to be resolved
    turnHistory: []
  };

  // Load player's spells
  if (typeof window.playerSpells !== 'undefined') {
    combatState.spells = [...window.playerSpells];
  }

  addLog('Combat started!', 'info');

  // Roll enemy intents
  rollAllEnemyIntents();

  // Transition to player status phase
  combatState.phase = 'player_status';
  processPlayerStartOfTurn();

  return combatState;
}

/**
 * Parse starting abilities from enemy ability string
 * @param {string} abilityStr - e.g., "Starts with Forgetful, Barricade"
 * @returns {Object} Status object
 */
function parseStartingAbilities(abilityStr) {
  const statuses = {};

  if (!abilityStr) return statuses;

  // Check for "Starts with X, Y"
  const startsWithMatch = abilityStr.match(/Starts with (.+)/i);
  if (startsWithMatch) {
    const statusList = startsWithMatch[1].split(',').map(s => s.trim());
    statusList.forEach(status => {
      // Check for "X Y" pattern (e.g., "2 Thorns")
      const numMatch = status.match(/^(\d+)\s+(.+)$/);
      if (numMatch) {
        statuses[numMatch[2].toLowerCase()] = parseInt(numMatch[1]);
      } else {
        statuses[status.toLowerCase()] = 1;
      }
    });
  }

  // Check for Fading X / Shifting
  const fadingMatch = abilityStr.match(/Fading (\d+)/i);
  if (fadingMatch) {
    statuses['fading'] = parseInt(fadingMatch[1]);
  }

  if (abilityStr.toLowerCase().includes('shifting')) {
    statuses['shifting'] = 1;
  }

  if (abilityStr.toLowerCase().includes('formless')) {
    statuses['formless'] = 1;
  }

  // Check for Multi Attack X
  const multiMatch = abilityStr.match(/Multi Attack (\d+)/i);
  if (multiMatch) {
    statuses['multi_attack'] = parseInt(multiMatch[1]);
  }

  return statuses;
}

/**
 * Roll intent for all enemies
 */
function rollAllEnemyIntents() {
  combatState.enemies.forEach(enemy => {
    if (enemy.health > 0) {
      rollEnemyIntent(enemy);
    }
  });
}

/**
 * Roll intent for a single enemy
 * @param {Object} enemy - Enemy state object
 */
function rollEnemyIntent(enemy) {
  if (!enemy.dice || enemy.dice.length === 0) return;

  // Check for Multi Attack
  const multiAttack = enemy.statuses['multi_attack'] || 1;

  enemy.currentIntent = [];

  for (let i = 0; i < multiAttack; i++) {
    // Roll random face
    const faceIndex = Math.floor(Math.random() * enemy.dice.length);
    const face = enemy.dice[faceIndex];

    enemy.currentIntent.push({
      faceIndex: faceIndex,
      face: face,
      resolved: false
    });
  }

  // Log intent
  const intentStr = enemy.currentIntent.map(intent => intent.face.raw || 'Unknown').join(', ');
  addLog(`${enemy.name} intends: ${intentStr}`, 'warning');
}

// ============== PLAYER ACTIONS ==============

/**
 * Roll a player die
 * @param {string} diceId - ID of the die to roll
 * @returns {Object} Result with success status and face
 */
function rollPlayerDie(diceId) {
  if (!combatState || combatState.phase !== 'player_action') {
    return { success: false, error: 'Cannot roll dice now' };
  }

  const die = combatState.playerDice.find(d => d.id === diceId);
  if (!die) {
    return { success: false, error: 'Die not found' };
  }

  if (die.isExhausted) {
    return { success: false, error: 'Die is exhausted' };
  }

  // Check ally is alive for ally dice
  if (die.source === 'ally') {
    const ally = combatState.allies.find(a => a.id === die.id);
    if (!ally || !ally.isAlive) {
      return { success: false, error: 'Ally is dead' };
    }
  }

  // Calculate energy cost (may be randomized by Confused)
  let energyCost = die.energyCost;
  const confusedStacks = combatState.player.statuses['confused'] || 0;
  if (confusedStacks > 0) {
    energyCost = Math.floor(Math.random() * (combatState.player.maxEnergy + 1));
    addLog(`Confused! Die costs ${energyCost} energy`, 'warning');
  }

  // Check energy
  if (combatState.player.energy < energyCost) {
    return { success: false, error: 'Not enough energy' };
  }

  // Spend energy
  combatState.player.energy -= energyCost;

  // Roll the die
  const faceIndex = Math.floor(Math.random() * die.faces.length);
  const face = die.faces[faceIndex];

  die.currentFace = face;
  die.currentFaceIndex = faceIndex;
  die.isRolled = true;
  die.isConfirmed = false;

  addLog(`Rolled ${die.name}: ${face.raw || 'Blank'}`, 'info');

  // Process Cantrip effects immediately
  if (!face.isBlank) {
    face.effects.forEach(effect => {
      if (effect.addons && effect.addons.includes('Cantrip')) {
        processCantripEffect(effect, die);
      }
    });
  }

  return { success: true, face: face, diceId: diceId, faceIndex: faceIndex };
}

/**
 * Reroll a player die
 * @param {string} diceId - ID of the die to reroll
 * @returns {Object} Result
 */
function rerollPlayerDie(diceId) {
  if (!combatState || combatState.phase !== 'player_action') {
    return { success: false, error: 'Cannot reroll now' };
  }

  const die = combatState.playerDice.find(d => d.id === diceId);
  if (!die || !die.isRolled || die.isConfirmed) {
    return { success: false, error: 'Cannot reroll this die' };
  }

  if (combatState.player.rerolls < 1) {
    return { success: false, error: 'No rerolls remaining' };
  }

  // Spend reroll
  combatState.player.rerolls--;

  // Reroll
  const faceIndex = Math.floor(Math.random() * die.faces.length);
  const face = die.faces[faceIndex];

  die.currentFace = face;
  die.currentFaceIndex = faceIndex;

  addLog(`Rerolled ${die.name}: ${face.raw || 'Blank'}`, 'info');

  // Process Cantrip effects
  if (!face.isBlank) {
    face.effects.forEach(effect => {
      if (effect.addons && effect.addons.includes('Cantrip')) {
        processCantripEffect(effect, die);
      }
    });
  }

  return { success: true, face: face, diceId: diceId, faceIndex: faceIndex };
}

/**
 * Confirm a die roll and apply effects
 * Dice can be used multiple times per turn as long as player has energy
 * @param {string} diceId - ID of the die
 * @param {Object} targets - Target information { enemyId, allyId, etc. }
 * @returns {Object} Result
 */
function confirmDie(diceId, targets = {}) {
  if (!combatState || combatState.phase !== 'player_action') {
    return { success: false, error: 'Cannot confirm now' };
  }

  const die = combatState.playerDice.find(d => d.id === diceId);
  if (!die || !die.isRolled) {
    return { success: false, error: 'Cannot confirm this die' };
  }

  const face = die.currentFace;

  // Process effects (skip Cantrip effects as they were already processed)
  if (!face.isBlank) {
    face.effects.forEach(effect => {
      if (!effect.addons || !effect.addons.includes('Cantrip')) {
        processEffect(effect, die, targets);
      }
    });
  }

  // Check for Exhert
  let hasExhert = false;
  if (face.effects) {
    face.effects.forEach(effect => {
      if (effect.addons) {
        const exhertAddon = effect.addons.find(a => a.startsWith('Exhert'));
        if (exhertAddon) {
          hasExhert = true;
          die.isExhausted = true;
          // Parse duration if present
          const match = exhertAddon.match(/Exhert\s*\((\d+)\)/i);
          die.exhertDuration = match ? parseInt(match[1]) : Infinity;
          addLog(`${die.name} is exhausted!`, 'warning');
        }
      }
    });
  }

  // Reset dice state so it can be rolled again (unless exhausted)
  if (!hasExhert) {
    die.isRolled = false;
    die.isConfirmed = false;
    die.currentFace = null;
    die.currentFaceIndex = null;
  } else {
    die.isConfirmed = true;
  }

  return { success: true };
}

/**
 * Use player's dash to gain Dodge
 * @returns {Object} Result
 */
function useDash() {
  if (!combatState || combatState.phase !== 'player_action') {
    return { success: false, error: 'Cannot dash now' };
  }

  if (combatState.player.dash < 1) {
    return { success: false, error: 'No dash available' };
  }

  // Calculate energy cost (may be randomized by Confused)
  let energyCost = 1;
  const confusedStacks = combatState.player.statuses['confused'] || 0;
  if (confusedStacks > 0) {
    energyCost = Math.floor(Math.random() * (combatState.player.maxEnergy + 1));
    addLog(`Confused! Dash costs ${energyCost} energy`, 'warning');
  }

  if (combatState.player.energy < energyCost) {
    return { success: false, error: 'Not enough energy' };
  }

  // Spend energy and dash
  combatState.player.energy -= energyCost;
  combatState.player.dash--;

  // Gain Dodge
  combatState.player.statuses['dodge'] = (combatState.player.statuses['dodge'] || 0) + 1;

  // Check for Ruptured
  const rupturedStacks = combatState.player.statuses['ruptured'] || 0;
  if (rupturedStacks > 0) {
    const damage = 3 * rupturedStacks;
    combatState.player.health -= damage;
    combatState.player.statuses['ruptured']--;
    if (combatState.player.statuses['ruptured'] <= 0) {
      delete combatState.player.statuses['ruptured'];
    }
    addLog(`Ruptured! Took ${damage} damage from dashing`, 'danger');
  }

  addLog('Used Dash to gain 1 Dodge!', 'success');

  return { success: true };
}

// ============== SPELL SYSTEM ==============

/**
 * Cast a spell
 * @param {string} spellName - Name of the spell
 * @param {Object} targets - Target information
 * @returns {Object} Result
 */
function castSpell(spellName, targets = {}) {
  if (!combatState || combatState.phase !== 'player_action') {
    return { success: false, error: 'Cannot cast spells now' };
  }

  // Find spell
  const spell = combatState.spells.find(s => s.name === spellName);
  if (!spell) {
    return { success: false, error: 'Spell not found' };
  }

  // Check SingleCast
  if (spell.keywords.includes('SingleCast') && combatState.usedSingleCast[spellName]) {
    return { success: false, error: 'Already used this combat' };
  }

  // Check Cooldown
  if (spell.keywords.includes('Cooldown') && combatState.spellCooldowns[spellName]) {
    return { success: false, error: 'On cooldown' };
  }

  // Calculate mana cost
  let cost = spell.cost;
  const castCount = combatState.spellCasts[spellName] || 0;

  // Channel: costs 1 less each cast (min 1)
  if (spell.keywords.includes('Channel')) {
    cost = Math.max(1, cost - castCount);
  }

  // Deplete: costs 1 more each cast
  if (spell.keywords.includes('Deplete')) {
    cost = cost + castCount;
  }

  // Check mana
  if (combatState.player.mana < cost) {
    return { success: false, error: 'Not enough mana' };
  }

  // Spend mana
  combatState.player.mana -= cost;

  // Track casts
  combatState.spellCasts[spellName] = castCount + 1;

  // Set cooldown
  if (spell.keywords.includes('Cooldown')) {
    combatState.spellCooldowns[spellName] = true;
  }

  // Mark SingleCast as used
  if (spell.keywords.includes('SingleCast')) {
    combatState.usedSingleCast[spellName] = true;
  }

  addLog(`Cast ${spellName}!`, 'info');

  // Process spell effects
  // Calculate INT bonus if applicable
  const intBonus = spell.affectedByBonus ? combatState.player.bonuses.intelligence : 0;

  spell.effects.forEach(effect => {
    // Clone effect and apply INT bonus
    const modifiedEffect = { ...effect };
    if (modifiedEffect.value && spell.affectedByBonus) {
      modifiedEffect.value += intBonus;
    }
    processSpellEffect(modifiedEffect, spell, targets);
  });

  // Check for Future keyword - delay effect to next turn
  if (spell.keywords.includes('Future')) {
    // Effects are queued for next turn start
    // This would need additional implementation
  }

  return { success: true };
}

// ============== EFFECT PROCESSING ==============

/**
 * Process a Cantrip effect (triggers immediately on roll)
 * @param {Object} effect - Effect data
 * @param {Object} die - Die that rolled this effect
 */
function processCantripEffect(effect, die) {
  // Auto-target based on preferred target
  const targets = getAutoTargets(effect);
  processEffect(effect, die, targets, true);
  addLog(`Cantrip: ${effect.raw}`, 'info');
}

/**
 * Process an effect from a die face
 * @param {Object} effect - Effect data
 * @param {Object} die - Die source
 * @param {Object} targets - Target information
 * @param {boolean} isCantrip - Whether this is a cantrip (auto-targeted)
 */
function processEffect(effect, die, targets, isCantrip = false) {
  if (!effect || !effect.move) return;

  const move = effect.move.toLowerCase();
  let value = effect.value || 0;

  // Apply stat bonuses
  value = applyStatBonus(move, value, die);

  // Get targets based on addons
  const resolvedTargets = resolveTargets(effect, targets, isCantrip);

  console.log('processEffect:', { move, value, targets, resolvedTargets, isCantrip });

  // Process based on move type
  switch (move) {
    case 'dmg':
      console.log('Processing dmg, enemies to target:', resolvedTargets.enemies.length);
      if (resolvedTargets.enemies.length === 0) {
        console.warn('No enemies to deal damage to! Targets:', targets);
      }
      resolvedTargets.enemies.forEach(enemy => {
        console.log('Dealing', value, 'damage to', enemy.name);
        dealDamage(enemy, value, effect.addons || []);
      });
      break;

    case 'block':
      resolvedTargets.allies.forEach(ally => {
        addBlock(ally, value);
      });
      if (resolvedTargets.player) {
        addBlock(combatState.player, value);
      }
      break;

    case 'heal':
      resolvedTargets.allies.forEach(ally => {
        healTarget(ally, value);
      });
      if (resolvedTargets.player) {
        healTarget(combatState.player, value);
      }
      break;

    case 'mana':
      combatState.player.mana = Math.min(
        combatState.player.mana + value,
        combatState.player.maxMana
      );
      addLog(`Gained ${value} mana`, 'info');
      break;

    case 'reroll':
      combatState.player.rerolls += value;
      addLog(`Gained ${value} reroll(s)`, 'info');
      break;

    case 'pain':
      dealDamage(combatState.player, value, ['self']);
      break;

    case 'get':
      // Give status to self
      const statusName = effect.target ? effect.target.toLowerCase() : '';
      if (statusName) {
        combatState.player.statuses[statusName] = (combatState.player.statuses[statusName] || 0) + value;
        addLog(`Gained ${value} ${effect.target}`, 'info');
      }
      break;

    case 'inflict':
      // Inflict status on targets
      const inflictStatus = effect.target ? effect.target.toLowerCase() : '';
      if (inflictStatus) {
        resolvedTargets.enemies.forEach(enemy => {
          enemy.statuses[inflictStatus] = (enemy.statuses[inflictStatus] || 0) + value;
          addLog(`Inflicted ${value} ${effect.target} on ${enemy.name}`, 'info');
        });
      }
      break;

    case 'cleanse':
      // Remove debuffs
      if (resolvedTargets.player) {
        cleanseDebuffs(combatState.player, value);
      }
      resolvedTargets.allies.forEach(ally => {
        cleanseDebuffs(ally, value);
      });
      break;

    case 'spawn':
      // Spawn creature - would need creature data
      addLog(`Spawned ${effect.target || 'creature'}`, 'info');
      break;

    case 'alter':
      // Transform - would need form data
      addLog(`Altered into ${effect.target || 'new form'}`, 'info');
      break;

    case 'assassinate':
      // Kill enemy if health <= value
      resolvedTargets.enemies.forEach(enemy => {
        if (enemy.health <= value) {
          enemy.health = 0;
          addLog(`Assassinated ${enemy.name}!`, 'success');
        }
      });
      break;

    case 'vitality':
      combatState.player.maxHealth += value;
      combatState.player.health += value;
      addLog(`Gained ${value} max health`, 'success');
      break;
  }
}

/**
 * Apply stat bonus to a move value
 * @param {string} move - Move type
 * @param {number} value - Base value
 * @param {Object} die - Die source (for weapon finesse check)
 * @returns {number} Modified value
 */
function applyStatBonus(move, value, die) {
  const bonuses = combatState.player.bonuses;

  // Check for Finesse on weapons
  const hasFinesse = die && die.tags && die.tags.includes('finesse');

  switch (move) {
    case 'dmg':
    case 'pain':
    case 'assassinate':
      return value + (hasFinesse ? bonuses.dexterity : bonuses.strength);

    case 'block':
      return value + bonuses.dexterity;

    case 'heal':
    case 'mana':
    case 'vitality':
      return value + bonuses.intelligence;

    case 'reroll':
    case 'get':
    case 'inflict':
    case 'cleanse':
      return value + bonuses.charisma;

    default:
      return value;
  }
}

/**
 * Resolve targets based on effect addons
 * @param {Object} effect - Effect data
 * @param {Object} targets - Specified targets
 * @param {boolean} isCantrip - Auto-target for cantrip
 * @returns {Object} Resolved targets { enemies: [], allies: [], player: bool }
 */
function resolveTargets(effect, targets, isCantrip) {
  const result = { enemies: [], allies: [], player: false };
  const addons = effect.addons || [];

  // Get preferred target from MOVES_DATA
  const moveData = typeof MOVES_DATA !== 'undefined' ? MOVES_DATA[effect.move?.toLowerCase()] : null;
  const preferredTarget = moveData?.preferredTarget || 'Enemy';

  // Wide: all enemies (for damage) or all allies (for support)
  if (addons.includes('Wide')) {
    if (preferredTarget === 'Enemy') {
      result.enemies = combatState.enemies.filter(e => e.health > 0);
    } else {
      result.allies = combatState.allies.filter(a => a.isAlive);
      result.player = true;
    }
    return result;
  }

  // Overload: everything
  if (addons.includes('Overload')) {
    result.enemies = combatState.enemies.filter(e => e.health > 0);
    result.allies = combatState.allies.filter(a => a.isAlive);
    result.player = true;
    return result;
  }

  // Cleave: target + adjacent
  if (addons.includes('Cleave') && targets.enemyId) {
    const targetEnemy = combatState.enemies.find(e => e.id === targets.enemyId);
    if (targetEnemy) {
      result.enemies.push(targetEnemy);
      // Add adjacent enemies
      const pos = targetEnemy.position;
      combatState.enemies.forEach(e => {
        if (e.health > 0 && (e.position === pos - 1 || e.position === pos + 1)) {
          result.enemies.push(e);
        }
      });
    }
    return result;
  }

  // Single target
  if (isCantrip) {
    // Auto-target for cantrip
    if (preferredTarget === 'Enemy') {
      const aliveEnemies = combatState.enemies.filter(e => e.health > 0);
      if (aliveEnemies.length > 0) {
        result.enemies.push(aliveEnemies[Math.floor(Math.random() * aliveEnemies.length)]);
      }
    } else {
      result.player = true;
    }
  } else {
    // Use specified target
    if (targets.enemyId) {
      const enemy = combatState.enemies.find(e => e.id === targets.enemyId);
      if (enemy) result.enemies.push(enemy);
    }
    if (targets.allyId) {
      const ally = combatState.allies.find(a => a.id === targets.allyId);
      if (ally) result.allies.push(ally);
    }
    if (targets.self || preferredTarget.includes('Self')) {
      result.player = true;
    }
  }

  // Default to player for self-targeting moves
  if (result.enemies.length === 0 && result.allies.length === 0 && !result.player) {
    if (preferredTarget.includes('Self') || preferredTarget.includes('Ally')) {
      result.player = true;
    }
  }

  return result;
}

/**
 * Get auto-targets for an effect
 * @param {Object} effect - Effect data
 * @returns {Object} Targets
 */
function getAutoTargets(effect) {
  const moveData = typeof MOVES_DATA !== 'undefined' ? MOVES_DATA[effect.move?.toLowerCase()] : null;
  const preferredTarget = moveData?.preferredTarget || 'Enemy';

  if (preferredTarget === 'Enemy') {
    const aliveEnemies = combatState.enemies.filter(e => e.health > 0);
    if (aliveEnemies.length > 0) {
      return { enemyId: aliveEnemies[Math.floor(Math.random() * aliveEnemies.length)].id };
    }
  }

  return { self: true };
}

// ============== COMBAT ACTIONS ==============

/**
 * Deal damage to a target
 * @param {Object} target - Target entity
 * @param {number} damage - Damage amount
 * @param {Array} addons - Effect addons
 */
function dealDamage(target, damage, addons = []) {
  if (damage <= 0) return;

  // Check Engage (x2 on full health)
  if (addons.includes('Engage') && target.health === target.maxHealth) {
    damage *= 2;
  }

  // Check Frail (double damage)
  const frailStacks = target.statuses['frail'] || 0;
  if (frailStacks > 0) {
    damage *= 2;
  }

  // Check Dodge
  const dodgeStacks = target.statuses['dodge'] || 0;
  if (dodgeStacks > 0 && !addons.includes('self')) {
    target.statuses['dodge']--;
    if (target.statuses['dodge'] <= 0) {
      delete target.statuses['dodge'];
    }
    addLog(`${target.name || 'Player'} dodged the attack!`, 'info');
    return;
  }

  // Apply Power modifier
  const powerStacks = target === combatState.player ? 0 : (target.statuses['power'] || 0);
  // Power affects outgoing damage, not incoming - skip for now

  // Apply block first
  let remainingDamage = damage;
  if (target.block > 0) {
    const blocked = Math.min(target.block, remainingDamage);
    target.block -= blocked;
    remainingDamage -= blocked;
    addLog(`${blocked} damage blocked`, 'info');
  }

  // Deal remaining damage to health
  if (remainingDamage > 0) {
    target.health -= remainingDamage;
    addLog(`${target.name || 'Player'} took ${remainingDamage} damage`, 'danger');

    // Check Thorns
    if (target.statuses['thorns'] && !addons.includes('self') && !addons.includes('Ranged')) {
      const thornsDamage = target.statuses['thorns'];
      combatState.player.health -= thornsDamage;
      addLog(`Thorns dealt ${thornsDamage} damage back!`, 'warning');
    }

    // Check Shifting
    if (target.statuses['shifting']) {
      target.statuses['power'] = (target.statuses['power'] || 0) - remainingDamage;
    }

    // Check Formless
    if (target.statuses['formless']) {
      rollEnemyIntent(target);
      addLog(`${target.name} rerolled intent due to Formless`, 'info');
    }
  }

  // Update global health if player
  if (target === combatState.player) {
    window.health = target.health;
  }
}

/**
 * Add block to a target
 * @param {Object} target - Target entity
 * @param {number} amount - Block amount
 */
function addBlock(target, amount) {
  if (amount <= 0) return;
  target.block = (target.block || 0) + amount;
  addLog(`${target.name || 'Player'} gained ${amount} block`, 'info');
}

/**
 * Heal a target
 * @param {Object} target - Target entity
 * @param {number} amount - Heal amount
 */
function healTarget(target, amount) {
  // Validate inputs
  const healAmount = (typeof amount === 'number' && !isNaN(amount)) ? amount : 0;
  if (healAmount <= 0) return;

  // Ensure target has valid health values
  const currentHealth = (typeof target.health === 'number' && !isNaN(target.health)) ? target.health : 0;
  const maxHealth = (typeof target.maxHealth === 'number' && !isNaN(target.maxHealth)) ? target.maxHealth : currentHealth;

  const healed = Math.min(healAmount, maxHealth - currentHealth);
  target.health = currentHealth + healed;
  addLog(`${target.name || 'Player'} healed ${healed}`, 'success');

  if (target === combatState.player) {
    window.health = target.health;
  }
}

/**
 * Cleanse debuffs from a target
 * @param {Object} target - Target entity
 * @param {number} stacks - Stacks to remove per debuff
 */
function cleanseDebuffs(target, stacks) {
  const debuffs = ['burn', 'poison', 'oiled', 'frail', 'ruptured', 'confused', 'fading'];

  debuffs.forEach(debuff => {
    if (target.statuses[debuff]) {
      target.statuses[debuff] = Math.max(0, target.statuses[debuff] - stacks);
      if (target.statuses[debuff] <= 0) {
        delete target.statuses[debuff];
      }
    }
  });

  addLog(`Cleansed ${stacks} stacks of debuffs`, 'success');
}

/**
 * Process spell effect (similar to die effect but with spell-specific handling)
 * @param {Object} effect - Effect data
 * @param {Object} spell - Spell data
 * @param {Object} targets - Targets
 */
function processSpellEffect(effect, spell, targets) {
  // Handle special spell descriptions
  const desc = spell.description.toLowerCase();

  // Kill effects
  if (desc.includes('kill an enemy')) {
    const aliveEnemies = combatState.enemies.filter(e => e.health > 0);

    if (desc.includes('with exactly 1 health')) {
      aliveEnemies.forEach(e => {
        if (e.health === 1) {
          e.health = 0;
          addLog(`${spell.name} killed ${e.name}!`, 'success');
          // Harvest: gain mana
          if (desc.includes('gain 3 mana')) {
            combatState.player.mana = Math.min(combatState.player.mana + 3, combatState.player.maxMana);
          }
        }
      });
    } else if (desc.includes('with exactly 2 health')) {
      aliveEnemies.forEach(e => {
        if (e.health === 2) {
          e.health = 0;
          addLog(`${spell.name} killed ${e.name}!`, 'success');
        }
      });
    } else if (desc.includes('half or less health')) {
      const target = targets.enemyId ?
        combatState.enemies.find(e => e.id === targets.enemyId) :
        aliveEnemies[0];
      if (target && target.health <= target.maxHealth / 2) {
        target.health = 0;
        addLog(`${spell.name} killed ${target.name}!`, 'success');
      }
    } else {
      // Kill any enemy (Infinity)
      const target = targets.enemyId ?
        combatState.enemies.find(e => e.id === targets.enemyId) :
        aliveEnemies[0];
      if (target) {
        target.health = 0;
        addLog(`${spell.name} killed ${target.name}!`, 'success');
      }
    }
    return;
  }

  // Set health effects (Mend)
  if (desc.includes('set self/ally to')) {
    const match = desc.match(/set self\/ally to (\d+) health/i);
    if (match) {
      const targetHealth = parseInt(match[1]);
      if (targets.allyId) {
        const ally = combatState.allies.find(a => a.id === targets.allyId);
        if (ally) ally.health = Math.min(targetHealth, ally.maxHealth);
      } else {
        combatState.player.health = Math.min(targetHealth, combatState.player.maxHealth);
        window.health = combatState.player.health;
      }
      addLog(`Set health to ${targetHealth}`, 'info');
    }
    return;
  }

  // Standard effect processing
  processEffect(effect, null, targets);
}

// ============== TURN MANAGEMENT ==============

/**
 * Process player's start of turn
 */
function processPlayerStartOfTurn() {
  combatState.phase = 'player_action';

  // Process player status effects
  processStatusEffects(combatState.player, 'start');

  // Reset cooldowns
  combatState.spellCooldowns = {};

  // Reset energy
  combatState.player.energy = combatState.player.maxEnergy;

  // Reset dice states
  combatState.playerDice.forEach(die => {
    die.isRolled = false;
    die.isConfirmed = false;
    die.currentFace = null;

    // Reduce exhert duration
    if (die.isExhausted && die.exhertDuration !== Infinity) {
      die.exhertDuration--;
      if (die.exhertDuration <= 0) {
        die.isExhausted = false;
        addLog(`${die.name} is no longer exhausted`, 'info');
      }
    }
  });

  // Check for Horn Cleat on turn 2
  if (combatState.turn === 2 && typeof inventory !== 'undefined') {
    const hasHornCleat = inventory.some(item => item.name === 'Horn Cleat');
    if (hasHornCleat) {
      addBlock(combatState.player, 5);
      addLog('Horn Cleat grants +5 Block!', 'success');
    }
  }

  addLog(`--- Turn ${combatState.turn} ---`, 'info');
}

/**
 * End the player's turn
 * @returns {Object} Result
 */
function endTurn() {
  if (!combatState || combatState.phase !== 'player_action') {
    return { success: false, error: 'Cannot end turn now' };
  }

  combatState.phase = 'end_turn';

  // Cap mana at max
  if (combatState.player.mana > combatState.player.maxMana) {
    combatState.player.mana = combatState.player.maxMana;
  }

  // Process enemy status effects
  combatState.enemies.forEach(enemy => {
    if (enemy.health > 0) {
      processStatusEffects(enemy, 'end');
    }
  });

  // Execute enemy actions
  executeEnemyActions();

  // Check for player defeat
  if (combatState.player.health <= 0) {
    combatState.phase = 'defeat';
    addLog('Defeated!', 'danger');
    return { success: true, phase: 'defeat' };
  }

  // Check for victory
  const allDead = combatState.enemies.every(e => e.health <= 0);
  if (allDead) {
    combatState.phase = 'victory';
    addLog('Victory!', 'success');
    return { success: true, phase: 'victory' };
  }

  // Reset block (unless Barricade)
  if (!combatState.player.statuses['barricade']) {
    combatState.player.block = 0;
  } else {
    combatState.player.block = Math.floor(combatState.player.block / 2);
  }

  // Process player end of turn status effects
  processStatusEffects(combatState.player, 'end');

  // Start new turn
  combatState.turn++;
  rollAllEnemyIntents();
  processPlayerStartOfTurn();

  return { success: true, phase: 'player_action' };
}

/**
 * Execute all enemy actions
 */
function executeEnemyActions() {
  combatState.enemies.forEach(enemy => {
    if (enemy.health <= 0) return;

    // Reset enemy block
    if (!enemy.statuses['barricade']) {
      enemy.block = 0;
    } else {
      enemy.block = Math.floor(enemy.block / 2);
    }

    // Execute intents
    if (enemy.currentIntent) {
      enemy.currentIntent.forEach(intent => {
        if (intent.resolved) return;

        const face = intent.face;
        if (face.isBlank) {
          addLog(`${enemy.name} does nothing`, 'info');
          return;
        }

        // Apply Power bonus to enemy damage
        const powerBonus = enemy.statuses['power'] || 0;

        face.effects.forEach(effect => {
          let value = effect.value || 0;

          // Add power bonus to damage
          if (effect.move?.toLowerCase() === 'dmg') {
            value += powerBonus;
          }

          // Process effect (targeting player)
          switch (effect.move?.toLowerCase()) {
            case 'dmg':
              dealDamageToPlayer(value, effect.addons || [], enemy);
              break;

            case 'block':
              addBlock(enemy, value);
              break;

            case 'heal':
              healTarget(enemy, value);
              break;

            case 'get':
              const statusName = effect.target?.toLowerCase();
              if (statusName) {
                enemy.statuses[statusName] = (enemy.statuses[statusName] || 0) + value;
                addLog(`${enemy.name} gained ${value} ${effect.target}`, 'info');
              }
              break;

            case 'inflict':
              const inflictStatus = effect.target?.toLowerCase();
              if (inflictStatus) {
                combatState.player.statuses[inflictStatus] =
                  (combatState.player.statuses[inflictStatus] || 0) + value;
                addLog(`${enemy.name} inflicted ${value} ${effect.target}`, 'warning');
              }
              break;

            case 'spawn':
              addLog(`${enemy.name} spawned ${effect.target || 'creature'}`, 'warning');
              break;

            case 'alter':
              addLog(`${enemy.name} altered form`, 'info');
              break;

            case 'pain':
              dealDamage(enemy, value, ['self']);
              break;
          }
        });

        intent.resolved = true;
      });
    }

    // Apply Ritual at end of turn
    if (enemy.statuses['ritual']) {
      enemy.statuses['power'] = (enemy.statuses['power'] || 0) + enemy.statuses['ritual'];
      addLog(`${enemy.name}'s Ritual grants ${enemy.statuses['ritual']} Power`, 'warning');
    }
  });
}

/**
 * Deal damage to the player from an enemy
 * @param {number} damage - Damage amount
 * @param {Array} addons - Effect addons
 * @param {Object} enemy - Attacking enemy
 */
function dealDamageToPlayer(damage, addons, enemy) {
  const player = combatState.player;

  // Check Frail
  if (player.statuses['frail']) {
    damage *= 2;
  }

  // Check Dodge
  if (player.statuses['dodge'] && player.statuses['dodge'] > 0) {
    player.statuses['dodge']--;
    if (player.statuses['dodge'] <= 0) {
      delete player.statuses['dodge'];
    }
    addLog('Dodged!', 'success');
    return;
  }

  // Apply block
  let remaining = damage;
  if (player.block > 0) {
    const blocked = Math.min(player.block, remaining);
    player.block -= blocked;
    remaining -= blocked;
    if (blocked > 0) {
      addLog(`Blocked ${blocked} damage`, 'info');
    }
  }

  // Deal damage
  if (remaining > 0) {
    player.health -= remaining;
    window.health = player.health;
    addLog(`${enemy.name} dealt ${remaining} damage!`, 'danger');
  }
}

/**
 * Process status effects on a target
 * @param {Object} target - Target entity
 * @param {string} timing - 'start' or 'end' of turn
 */
function processStatusEffects(target, timing) {
  const statuses = target.statuses;

  if (timing === 'start') {
    // Burn deals damage at start
    if (statuses['burn']) {
      const burnDamage = 3 * statuses['burn'];
      // Check Oiled (double burn damage)
      const multiplier = statuses['oiled'] ? 2 : 1;
      target.health -= burnDamage * multiplier;
      addLog(`Burn dealt ${burnDamage * multiplier} damage to ${target.name || 'Player'}`, 'danger');
      if (target === combatState.player) {
        window.health = target.health;
      }
    }

    // Poison deals damage at start
    if (statuses['poison']) {
      const poisonDamage = statuses['poison'];
      target.health -= poisonDamage;
      addLog(`Poison dealt ${poisonDamage} damage to ${target.name || 'Player'}`, 'danger');
      if (target === combatState.player) {
        window.health = target.health;
      }
    }
  }

  if (timing === 'end') {
    // Decay statuses
    const decayStatuses = ['burn', 'poison', 'oiled', 'frail', 'confused', 'barricade'];
    decayStatuses.forEach(status => {
      if (statuses[status]) {
        statuses[status]--;
        if (statuses[status] <= 0) {
          delete statuses[status];
        }
      }
    });

    // Fading
    if (statuses['fading']) {
      statuses['fading']--;
      if (statuses['fading'] <= 0) {
        target.health = 0;
        addLog(`${target.name} faded away!`, 'info');
      }
    }
  }
}

// ============== UTILITY ==============

/**
 * Add message to combat log
 * @param {string} message - Log message
 * @param {string} type - 'info', 'success', 'warning', 'danger'
 */
function addLog(message, type = 'info') {
  if (!combatState) return;

  combatState.log.push({
    message: message,
    type: type,
    timestamp: Date.now()
  });

  // Also log to console for debugging
  console.log(`[Combat] ${message}`);
}

/**
 * Get current combat state
 * @returns {Object} Combat state or null
 */
function getCombatState() {
  return combatState;
}

/**
 * End combat
 * @param {boolean} victory - Whether player won
 * @returns {Object} Combat result
 */
function endCombat(victory) {
  if (!combatState) return null;

  const result = {
    victory: victory,
    turns: combatState.turn,
    log: combatState.log
  };

  combatState = null;

  return result;
}

// ============== EXPORTS ==============

if (typeof window !== 'undefined') {
  window.CombatEngine = {
    initCombat,
    rollPlayerDie,
    rerollPlayerDie,
    confirmDie,
    useDash,
    castSpell,
    endTurn,
    getCombatState,
    endCombat,
    addLog
  };
}
