/**
 * Combat State Management
 * Manages the active combat state including enemies, player, effects, and turn flow
 */

// Active combat state (null when not in combat)
var activeCombat = null;

/**
 * Initialize a new combat encounter
 * @param {Object} enemy - Enemy data from ENEMIES_DATA
 * @returns {Object} Initialized combat state
 */
function initializeCombat(enemy) {
  // Create a copy of the enemy with combat-specific data
  const enemyState = {
    name: enemy.name,
    powerLevel: enemy.powerLevel,
    game: enemy.game,
    stat: enemy.stat,
    armorClass: enemy.armorClass,
    maxHealth: enemy.health,
    health: enemy.health,
    attack: enemy.attack,
    successReward: enemy.successReward,
    failureConsequence: enemy.failureConsequence,
    imageUrl: enemy.imageUrl,
    effects: window.CombatEffects.createEffects()
  };

  // Create player state snapshot
  const playerState = {
    health: health,
    maxHealth: maxHealth,
    attack: attack,
    strength: strength,
    dexterity: dexterity,
    intelligence: intelligence,
    charisma: charisma,
    effects: window.CombatEffects.createEffects()
  };

  // Create player's dice
  const playerDice = window.DiceSystem.createD20();

  // Initialize combat state
  activeCombat = {
    enemy: enemyState,
    player: playerState,
    dice: [playerDice],  // Array to support multiple dice in the future
    turn: 0,
    phase: 'player_turn',  // 'player_turn', 'enemy_turn', 'victory', 'defeat'
    log: [],  // Combat log for displaying what happened
    diceRolled: [],  // Track which dice have been rolled this turn
    actionsAvailable: {
      canRollDice: true,
      canUseItems: true,
      canEndTurn: true
    }
  };

  // Log combat start
  addCombatLog(`Combat started against ${enemy.name}!`);

  return activeCombat;
}

/**
 * Add a message to the combat log
 * @param {string} message - Message to add
 * @param {string} type - Type of message ('info', 'success', 'danger', 'warning')
 */
function addCombatLog(message, type = 'info') {
  if (activeCombat) {
    activeCombat.log.push({
      message: message,
      type: type,
      timestamp: Date.now()
    });
  }
}

/**
 * Roll a specific dice in combat
 * @param {number} diceIndex - Index of the dice to roll (default 0 for main D20)
 * @returns {Object} Roll result
 */
function rollCombatDice(diceIndex = 0) {
  if (!activeCombat) {
    throw new Error('No active combat');
  }

  if (activeCombat.phase !== 'player_turn') {
    throw new Error('Cannot roll dice during enemy turn');
  }

  if (diceIndex < 0 || diceIndex >= activeCombat.dice.length) {
    throw new Error('Invalid dice index');
  }

  // Check if this dice has already been rolled
  if (activeCombat.diceRolled.includes(diceIndex)) {
    throw new Error('This dice has already been rolled this turn');
  }

  // Roll the dice
  const dice = activeCombat.dice[diceIndex];
  const rollResult = window.DiceSystem.rollDice(dice);

  // Mark dice as rolled
  activeCombat.diceRolled.push(diceIndex);

  // Log the roll
  addCombatLog(`Rolled a ${rollResult.total}!`, 'info');

  return rollResult;
}

/**
 * Check if player's attack hits the enemy's AC
 * @param {number} rollTotal - Total roll value (dice + stat modifier)
 * @param {number} armorClass - Enemy's AC
 * @returns {boolean} True if the attack hits
 */
function checkHit(rollTotal, armorClass) {
  return rollTotal >= armorClass;
}

/**
 * Get the appropriate stat modifier for the current enemy
 * @returns {number} Stat modifier value
 */
function getStatModifier() {
  if (!activeCombat) {
    return 0;
  }

  const stat = activeCombat.enemy.stat;

  switch (stat) {
    case 'Strength':
      return activeCombat.player.strength;
    case 'Dexterity':
      return activeCombat.player.dexterity;
    case 'Intelligence':
      return activeCombat.player.intelligence;
    case 'Charisma':
      return activeCombat.player.charisma;
    default:
      return 0;
  }
}

/**
 * Execute the player's attack on the enemy
 * @param {number} rollTotal - Total roll value
 * @returns {Object} Attack result
 */
function executePlayerAttack(rollTotal) {
  if (!activeCombat) {
    throw new Error('No active combat');
  }

  const enemy = activeCombat.enemy;
  const statModifier = getStatModifier();
  const finalRoll = rollTotal + statModifier;

  // Check if attack hits
  const hits = checkHit(finalRoll, enemy.armorClass);

  if (hits) {
    // Deal damage equal to player's attack stat
    const damage = activeCombat.player.attack;

    // Apply damage through enemy's block
    const damageResult = window.CombatEffects.processDamageWithBlock(enemy, damage);

    addCombatLog(
      `Hit! Dealt ${damageResult.healthLost} damage to ${enemy.name}${
        damageResult.blockConsumed > 0 ? ` (${damageResult.blockConsumed} blocked)` : ''
      }`,
      'success'
    );

    return {
      hit: true,
      damage: damageResult.healthLost,
      blockConsumed: damageResult.blockConsumed,
      enemyHealth: enemy.health
    };
  } else {
    addCombatLog(`Miss! Roll ${finalRoll} did not meet AC ${enemy.armorClass}`, 'danger');

    return {
      hit: false,
      damage: 0,
      blockConsumed: 0,
      enemyHealth: enemy.health
    };
  }
}

/**
 * Execute the enemy's attack on the player
 * @returns {Object} Attack result
 */
function executeEnemyAttack() {
  if (!activeCombat) {
    throw new Error('No active combat');
  }

  const enemy = activeCombat.enemy;
  const player = activeCombat.player;
  const damage = enemy.attack;

  // Apply damage through player's block
  const damageResult = window.CombatEffects.processDamageWithBlock(player, damage);

  addCombatLog(
    `${enemy.name} attacks! Dealt ${damageResult.healthLost} damage${
      damageResult.blockConsumed > 0 ? ` (${damageResult.blockConsumed} blocked)` : ''
    }`,
    'danger'
  );

  // Update global health variable
  health = player.health;

  return {
    damage: damageResult.healthLost,
    blockConsumed: damageResult.blockConsumed,
    playerHealth: player.health
  };
}

/**
 * Apply a curse to the player based on enemy data
 */
function applyCurseToPlayer() {
  if (!activeCombat) {
    return;
  }

  const enemy = activeCombat.enemy;
  const failureConsequence = enemy.failureConsequence;

  // Parse curse type and power from failureConsequence (e.g., "Low Curse", "Medium Curse")
  const match = failureConsequence.match(/(Low|Medium|High)\s+Curse/i);

  if (match) {
    const curseType = match[1];
    addCombatLog(`You have been cursed! (${curseType})`, 'warning');

    // The actual curse application will be handled by the existing curse system
    // This is just a placeholder for the combat log
  }
}

/**
 * End the player's turn and transition to enemy turn
 * @returns {Object} Turn end result
 */
function endPlayerTurn() {
  if (!activeCombat) {
    throw new Error('No active combat');
  }

  if (activeCombat.phase !== 'player_turn') {
    throw new Error('Not in player turn phase');
  }

  // Check if dice have been rolled
  if (activeCombat.diceRolled.length === 0) {
    throw new Error('Must roll dice before ending turn');
  }

  // Get the main dice roll result
  const mainDice = activeCombat.dice[0];
  const rollResult = mainDice.currentRoll;

  if (!rollResult) {
    throw new Error('No roll result found');
  }

  // Execute player attack
  const attackResult = executePlayerAttack(rollResult.total);

  // Check if enemy is defeated
  if (activeCombat.enemy.health <= 0) {
    activeCombat.phase = 'victory';
    addCombatLog(`${activeCombat.enemy.name} defeated!`, 'success');
    return {
      phase: 'victory',
      attackResult: attackResult
    };
  }

  // Transition to enemy turn if attack missed
  if (!attackResult.hit) {
    activeCombat.phase = 'enemy_turn';

    // Execute enemy attack
    const enemyAttackResult = executeEnemyAttack();

    // Apply curse
    applyCurseToPlayer();

    // Process poison on player (if any)
    const poisonResult = window.CombatEffects.processPoisonDamage(activeCombat.player);
    if (poisonResult.poisonDamage > 0) {
      addCombatLog(`Poison dealt ${poisonResult.poisonDamage} damage!`, 'danger');
      health = activeCombat.player.health;
    }

    // Check if player is defeated
    if (activeCombat.player.health <= 0) {
      activeCombat.phase = 'defeat';
      addCombatLog('You have been defeated!', 'danger');
      health = 0;
      return {
        phase: 'defeat',
        attackResult: attackResult,
        enemyAttackResult: enemyAttackResult
      };
    }
  }

  // Clear block from both player and enemy at end of turn
  window.CombatEffects.clearBlock(activeCombat.player.effects);
  window.CombatEffects.clearBlock(activeCombat.enemy.effects);

  // Process poison on enemy (if any)
  const enemyPoisonResult = window.CombatEffects.processPoisonDamage(activeCombat.enemy);
  if (enemyPoisonResult.poisonDamage > 0) {
    addCombatLog(`${activeCombat.enemy.name} took ${enemyPoisonResult.poisonDamage} poison damage!`, 'success');

    // Check if enemy died from poison
    if (activeCombat.enemy.health <= 0) {
      activeCombat.phase = 'victory';
      addCombatLog(`${activeCombat.enemy.name} defeated by poison!`, 'success');
      return {
        phase: 'victory',
        attackResult: attackResult
      };
    }
  }

  // Start next turn
  activeCombat.turn++;
  activeCombat.phase = 'player_turn';
  activeCombat.diceRolled = [];

  addCombatLog(`--- Turn ${activeCombat.turn + 1} ---`, 'info');

  return {
    phase: 'player_turn',
    attackResult: attackResult,
    enemyAttackResult: attackResult.hit ? null : executeEnemyAttack
  };
}

/**
 * End combat and clean up state
 * @param {boolean} victory - True if player won
 * @returns {Object} Combat result
 */
function endCombat(victory) {
  if (!activeCombat) {
    return null;
  }

  const result = {
    victory: victory,
    enemy: activeCombat.enemy,
    turnCount: activeCombat.turn,
    log: activeCombat.log
  };

  activeCombat = null;

  return result;
}

/**
 * Get the current combat state (read-only)
 * @returns {Object} Current combat state or null
 */
function getCombatState() {
  return activeCombat;
}

// Export to global scope
if (typeof window !== 'undefined') {
  window.CombatState = {
    initializeCombat,
    addCombatLog,
    rollCombatDice,
    checkHit,
    getStatModifier,
    executePlayerAttack,
    executeEnemyAttack,
    applyCurseToPlayer,
    endPlayerTurn,
    endCombat,
    getCombatState
  };
}
