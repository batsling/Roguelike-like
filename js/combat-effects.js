/**
 * Combat Effects System
 * Handles status effects like block, poison, etc. for both player and enemies
 * Effects work similarly to Slay the Spire:
 * - Block: Absorbs damage, does not persist between turns (generally)
 * - Poison: Deals damage at end of turn, decrements by 1 each turn
 */

/**
 * Create a new effects object with default values
 * @returns {Object} Effects object with all status effects initialized to 0
 */
function createEffects() {
  return {
    block: 0,      // Damage mitigation that expires at end of turn
    poison: 0      // Damage dealt at end of turn, decrements by 1
  };
}

/**
 * Apply block to a target
 * @param {Object} effects - The target's effects object
 * @param {number} amount - Amount of block to add
 * @returns {Object} Updated effects object
 */
function applyBlock(effects, amount) {
  effects.block += amount;
  return effects;
}

/**
 * Apply poison to a target
 * @param {Object} effects - The target's effects object
 * @param {number} amount - Amount of poison to add
 * @returns {Object} Updated effects object
 */
function applyPoison(effects, amount) {
  effects.poison += amount;
  return effects;
}

/**
 * Process damage through block
 * Block absorbs damage first, then remaining damage goes to health
 * @param {Object} target - Target with effects and health
 * @param {number} damage - Incoming damage
 * @returns {Object} Result with damage dealt, block consumed, and updated target
 */
function processDamageWithBlock(target, damage) {
  let remainingDamage = damage;
  let blockConsumed = 0;

  // Block absorbs damage first
  if (target.effects.block > 0) {
    blockConsumed = Math.min(target.effects.block, damage);
    target.effects.block -= blockConsumed;
    remainingDamage -= blockConsumed;
  }

  // Remaining damage goes to health
  const healthLost = remainingDamage;
  target.health -= healthLost;

  return {
    blockConsumed: blockConsumed,
    healthLost: healthLost,
    totalDamage: damage,
    target: target
  };
}

/**
 * Process poison damage at the start/end of a turn
 * Deals damage equal to poison stacks, then reduces poison by 1
 * @param {Object} target - Target with effects and health
 * @returns {Object} Result with poison damage dealt and updated target
 */
function processPoisonDamage(target) {
  if (target.effects.poison <= 0) {
    return {
      poisonDamage: 0,
      target: target
    };
  }

  const poisonDamage = target.effects.poison;

  // Poison damage bypasses block and goes directly to health
  target.health -= poisonDamage;

  // Decrement poison by 1
  target.effects.poison = Math.max(0, target.effects.poison - 1);

  return {
    poisonDamage: poisonDamage,
    target: target
  };
}

/**
 * Clear all block at the end of a turn
 * @param {Object} effects - The effects object to clear block from
 * @returns {Object} Updated effects object
 */
function clearBlock(effects) {
  effects.block = 0;
  return effects;
}

/**
 * Reset all effects (used at the start of combat)
 * @param {Object} effects - The effects object to reset
 * @returns {Object} Cleared effects object
 */
function resetEffects(effects) {
  effects.block = 0;
  effects.poison = 0;
  return effects;
}

/**
 * Get a description of active effects for display
 * @param {Object} effects - The effects object to describe
 * @returns {Array<string>} Array of effect descriptions
 */
function getEffectDescriptions(effects) {
  const descriptions = [];

  if (effects.block > 0) {
    descriptions.push(`Block: ${effects.block}`);
  }

  if (effects.poison > 0) {
    descriptions.push(`Poison: ${effects.poison}`);
  }

  return descriptions;
}

/**
 * Check if a target has any active effects
 * @param {Object} effects - The effects object to check
 * @returns {boolean} True if any effects are active
 */
function hasActiveEffects(effects) {
  return effects.block > 0 || effects.poison > 0;
}

// Export to global scope
if (typeof window !== 'undefined') {
  window.CombatEffects = {
    createEffects,
    applyBlock,
    applyPoison,
    processDamageWithBlock,
    processPoisonDamage,
    clearBlock,
    resetEffects,
    getEffectDescriptions,
    hasActiveEffects
  };
}
