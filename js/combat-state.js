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
  // Create enemy dice based on difficulty
  let enemyDice;
  if (enemy.difficulty === 'Low') {
    enemyDice = window.DiceSystem.createEnemyD6Low();
  } else if (enemy.difficulty === 'Medium') {
    enemyDice = window.DiceSystem.createEnemyD6Medium();
  } else if (enemy.difficulty === 'High') {
    enemyDice = window.DiceSystem.createEnemyD6High();
  } else {
    // Default to low if difficulty not specified
    enemyDice = window.DiceSystem.createEnemyD6Low();
  }

  const enemyState = {
    name: enemy.name,
    powerLevel: enemy.powerLevel,
    game: enemy.game,
    stat: enemy.stat,
    difficulty: enemy.difficulty,
    armorClass: enemy.armorClass,
    maxHealth: enemy.health,
    health: enemy.health,
    attack: enemy.attack,  // Keep for backwards compatibility
    strength: 0,  // Bonus damage for attack dice
    defence: 0,   // Bonus block for defense dice
    successReward: enemy.successReward,
    failureConsequence: enemy.failureConsequence,
    imageUrl: enemy.imageUrl,
    effects: window.CombatEffects.createEffects(),
    plannedAction: null  // Will be set after rolling enemy dice
  };

  // Create player state snapshot with effective stats (including weapon bonuses)
  const getEffectiveStat = window.getEffectiveStat || ((statName) => window[statName] || 0);

  const playerState = {
    health: health,
    maxHealth: maxHealth,
    attack: typeof getEffectiveAttack === 'function' ? getEffectiveAttack() : attack,
    strength: getEffectiveStat('strength'),
    dexterity: getEffectiveStat('dexterity'),
    intelligence: getEffectiveStat('intelligence'),
    charisma: getEffectiveStat('charisma'),
    energy: gameState.energy || 2,  // Energy for actions this turn
    maxEnergy: gameState.maxEnergy || 2,  // Max energy per turn
    effects: window.CombatEffects.createEffects()
  };

  // Create player's dice - both Attack D20 and Defense D6
  const attackDice = window.DiceSystem.createD20();
  const defenseDice = window.DiceSystem.createDefenseD6();

  // Initialize combat state
  activeCombat = {
    enemy: enemyState,
    player: playerState,
    dice: {
      attack: attackDice,
      defense: defenseDice,
      enemy: enemyDice
    },
    turn: 0,
    phase: 'player_turn',  // 'player_turn', 'enemy_turn', 'victory', 'defeat'
    log: [],  // Combat log for displaying what happened
    diceRolled: {
      attack: false,
      defense: false
    },  // Track which dice have been rolled
    rollCount: {
      attack: 0,
      defense: 0
    },  // Track how many times each die was rolled this turn
    actionsAvailable: {
      canRollDice: true,
      canUseItems: true,
      canEndTurn: true
    }
  };

  // Log combat start
  addCombatLog(`Combat started against ${enemy.name}!`);

  // Roll enemy dice to set their initial intent
  rollEnemyDice();

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
 * @param {string} diceType - Type of dice to roll ('attack' or 'defense')
 * @returns {Object} Roll result with success/error info
 */
function rollCombatDice(diceType = 'attack') {
  if (!activeCombat) {
    throw new Error('No active combat');
  }

  if (activeCombat.phase !== 'player_turn') {
    throw new Error('Cannot roll dice during enemy turn');
  }

  if (!['attack', 'defense'].includes(diceType)) {
    throw new Error('Invalid dice type');
  }

  // Check if player has enough energy
  if (activeCombat.player.energy < 1) {
    return { success: false, error: 'Not enough energy' };
  }

  // Spend energy
  activeCombat.player.energy -= 1;

  // Check if player has Curse of Obstruction (Disadvantage) - only affects attack rolls
  const obstructionCurses = gameState.activeCurses ? gameState.activeCurses.filter(curse =>
    curse.name && curse.name.toLowerCase().includes('obstruction')
  ) : [];

  const hasObstruction = obstructionCurses.length > 0 && diceType === 'attack';

  // Roll the dice
  const dice = activeCombat.dice[diceType];
  let rollResult = window.DiceSystem.rollDice(dice);
  let roll1Value = rollResult.total;
  let roll2Value = null;

  // If player has Curse of Obstruction on attack roll, roll twice and take the lower
  if (hasObstruction) {
    const secondRollResult = window.DiceSystem.rollDice(dice);
    roll2Value = secondRollResult.total;

    // Take the lower of the two rolls
    if (roll2Value < roll1Value) {
      rollResult = secondRollResult;
    }

    // Log both rolls with visual distinction
    addCombatLog(`Curse of Obstruction! Rolled ${roll1Value} and ${roll2Value} → Taking lower: ${rollResult.total}`, 'warning');

    // Decrement obstruction curse duration (consume one roll)
    obstructionCurses.forEach(curse => {
      if (curse.duration && curse.duration.includes('Roll')) {
        // Parse the duration (e.g., "1 Roll", "2 Rolls", "3 Rolls")
        const rollsMatch = curse.duration.match(/(\d+)\s*Roll/i);
        if (rollsMatch) {
          const rollsRemaining = parseInt(rollsMatch[1]);
          if (rollsRemaining > 1) {
            // Decrement the roll count
            curse.duration = `${rollsRemaining - 1} Roll${rollsRemaining - 1 > 1 ? 's' : ''}`;
          } else {
            // Remove the curse (it was the last roll)
            if (typeof CurseManager !== 'undefined' && typeof CurseManager.consume === 'function') {
              CurseManager.consume(curse);
              addCombatLog(`Curse of Obstruction expired!`, 'info');
            }
          }
        }
      }
    });

    // Update curse UI
    if (typeof updateCurseUI === 'function') {
      updateCurseUI();
    }
  } else {
    // Normal roll (no disadvantage)
    if (diceType === 'attack') {
      addCombatLog(`Rolled attack: ${rollResult.total}!`, 'info');
    } else {
      addCombatLog(`Rolled defense: ${rollResult.total} block!`, 'info');
    }
  }

  // Track roll count
  activeCombat.rollCount[diceType]++;

  return { success: true, result: rollResult, diceType: diceType };
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
 * Roll enemy dice to determine their intent for this turn
 * @returns {Object} Planned action with type and value
 */
function rollEnemyDice() {
  if (!activeCombat) {
    throw new Error('No active combat');
  }

  const enemyDice = activeCombat.dice.enemy;
  const rollResult = window.DiceSystem.rollDice(enemyDice);
  const side = rollResult.side;

  // Determine planned action based on dice roll
  const plannedAction = {
    type: side.action,  // 'attack' or 'defend'
    value: side.value,
    displayText: side.displayText,
    sideIndex: rollResult.sideIndex + 1  // For display (1-6)
  };

  activeCombat.enemy.plannedAction = plannedAction;

  // Log the enemy's intent
  if (plannedAction.type === 'attack') {
    const totalDamage = plannedAction.value + activeCombat.enemy.strength;
    addCombatLog(`${activeCombat.enemy.name} plans to attack for ${totalDamage} damage!`, 'warning');
  } else {
    const totalBlock = plannedAction.value + activeCombat.enemy.defence;
    addCombatLog(`${activeCombat.enemy.name} plans to gain ${totalBlock} block!`, 'info');
  }

  return plannedAction;
}

/**
 * Execute the enemy's planned action
 * @returns {Object} Action result
 */
function executeEnemyAction() {
  if (!activeCombat) {
    throw new Error('No active combat');
  }

  const enemy = activeCombat.enemy;
  const player = activeCombat.player;
  const plannedAction = enemy.plannedAction;

  if (!plannedAction) {
    throw new Error('No planned action for enemy');
  }

  if (plannedAction.type === 'attack') {
    // Execute attack
    const damage = plannedAction.value + enemy.strength;

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
      type: 'attack',
      damage: damageResult.healthLost,
      blockConsumed: damageResult.blockConsumed,
      playerHealth: player.health
    };
  } else {
    // Execute defense
    const blockGained = plannedAction.value + enemy.defence;

    if (typeof window.CombatEffects !== 'undefined' && typeof window.CombatEffects.addBlock === 'function') {
      window.CombatEffects.addBlock(enemy, blockGained);
    } else {
      enemy.effects.block = (enemy.effects.block || 0) + blockGained;
    }

    addCombatLog(`${enemy.name} gains ${blockGained} block!`, 'info');

    return {
      type: 'defend',
      blockGained: blockGained,
      enemyBlock: enemy.effects.block
    };
  }
}

/**
 * Execute the enemy's attack on the player (legacy - kept for backwards compatibility)
 * @returns {Object} Attack result
 */
function executeEnemyAttack() {
  // Use new executeEnemyAction function
  return executeEnemyAction();
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

  // Parse curse power from failureConsequence (e.g., "Low Curse", "Medium Curse")
  const match = failureConsequence.match(/(Low|Medium|High)\s+Curse/i);

  if (match) {
    const cursePower = match[1];

    // Find a curse that matches the enemy's stat and the power level
    if (typeof CURSES_DATA !== 'undefined') {
      const matchingCurses = CURSES_DATA.filter(curse =>
        curse.stat === enemy.stat && curse.power === cursePower
      );

      if (matchingCurses.length > 0) {
        // Pick a random curse from matching ones
        const randomCurse = matchingCurses[Math.floor(Math.random() * matchingCurses.length)];

        // Apply the curse using the global addCurse function
        if (typeof addCurse === 'function') {
          addCurse(randomCurse.name);
          addCombatLog(`Cursed with ${randomCurse.name}!`, 'warning');
        } else {
          addCombatLog(`You have been cursed! (${cursePower})`, 'warning');
        }
      } else {
        console.warn(`No curse found for stat ${enemy.stat} with power ${cursePower}`);
        addCombatLog(`You have been cursed! (${cursePower})`, 'warning');
      }
    } else {
      console.warn('CURSES_DATA not available');
      addCombatLog(`You have been cursed! (${cursePower})`, 'warning');
    }
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

  // In the new energy system, player doesn't need to roll - they can end turn with unused energy
  // No validation needed here

  // Check if enemy is already defeated (from successful attack during player turn)
  if (activeCombat.enemy.health <= 0) {
    activeCombat.phase = 'victory';
    addCombatLog(`${activeCombat.enemy.name} defeated!`, 'success');
    return {
      phase: 'victory'
    };
  }

  // Enemy turn always happens (unless enemy is already dead)
  activeCombat.phase = 'enemy_turn';

  // Reset enemy block from last turn before executing new action
  activeCombat.enemy.effects.block = 0;

  // Execute enemy's planned action
  const enemyActionResult = executeEnemyAction();

  // Apply curse (if player took damage from enemy attack)
  if (enemyActionResult.type === 'attack' && enemyActionResult.damage > 0) {
    applyCurseToPlayer();
  }

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
      enemyActionResult: enemyActionResult
    };
  }

  // Process poison on enemy (if any)
  const enemyPoisonResult = window.CombatEffects.processPoisonDamage(activeCombat.enemy);
  if (enemyPoisonResult.poisonDamage > 0) {
    addCombatLog(`${activeCombat.enemy.name} took ${enemyPoisonResult.poisonDamage} poison damage!`, 'success');

    // Check if enemy died from poison
    if (activeCombat.enemy.health <= 0) {
      activeCombat.phase = 'victory';
      addCombatLog(`${activeCombat.enemy.name} defeated by poison!`, 'success');
      return {
        phase: 'victory'
      };
    }
  }

  // Start next turn
  activeCombat.turn++;
  activeCombat.phase = 'player_turn';

  // Reset roll counts for new turn
  activeCombat.rollCount.attack = 0;
  activeCombat.rollCount.defense = 0;

  // Reset only player block at start of player turn (enemy block was already reset)
  activeCombat.player.effects.block = 0;

  addCombatLog(`--- Turn ${activeCombat.turn + 1} ---`, 'info');

  // Roll enemy dice to set their intent for this turn
  rollEnemyDice();

  // Check for Calipers: grants +5 block on turn 2 (when turn === 1)
  if (activeCombat.turn === 1) {
    const hasCalipers = inventory.some(item => item.name === 'Calipers');
    if (hasCalipers) {
      // Calculate Calipers block value (base 5, can be modified by upgrades/downgrades)
      const calipersItem = inventory.find(item => item.name === 'Calipers');
      let blockAmount = 5;

      // Apply upgrade/downgrade modifiers if present
      if (calipersItem && calipersItem.statModifiers) {
        blockAmount += calipersItem.statModifiers.block || 0;
      }

      if (blockAmount > 0) {
        if (typeof window.CombatEffects !== 'undefined' && typeof window.CombatEffects.addBlock === 'function') {
          window.CombatEffects.addBlock(activeCombat.player, blockAmount);
        } else {
          activeCombat.player.effects.block += blockAmount;
        }
        addCombatLog(`Calipers grants +${blockAmount} Block!`, 'success');
      }
    }
  }

  return {
    phase: 'player_turn'
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
    rollEnemyDice,
    checkHit,
    getStatModifier,
    executePlayerAttack,
    executeEnemyAction,
    executeEnemyAttack,
    applyCurseToPlayer,
    endPlayerTurn,
    endCombat,
    getCombatState
  };
}
