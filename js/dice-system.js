/**
 * Dice System
 * Handles dice data structures with individual sides that can be modified
 * Future-proof design allows for side modifications, bonuses, and multiple dice types
 */

/**
 * Create a standard D20 with default sides (1-20)
 * Each side can be modified individually in the future
 * @returns {Object} D20 dice object
 */
function createD20() {
  const sides = [];

  // Create 20 sides with default values
  for (let i = 1; i <= 20; i++) {
    sides.push({
      value: i,              // The numeric value of this side
      texture: null,         // Optional texture/image for this side (for future use)
      modifiers: [],         // Array of modifiers that affect this side (for future use)
      displayValue: null     // Optional display value override (for future use)
    });
  }

  return {
    type: 'd20',
    sides: sides,
    globalModifiers: [],     // Modifiers that affect all sides (e.g., "+2 to all rolls")
    currentRoll: null        // The result of the most recent roll
  };
}

/**
 * Create a Defense D6 with specific block values
 * Face distribution: 1🛡️, 2🛡️, 2🛡️, 3🛡️, 3🛡️, 4🛡️
 * @returns {Object} Defense D6 dice object
 */
function createDefenseD6() {
  // Block values for each face (index 0-5)
  const blockValues = [1, 2, 2, 3, 3, 4];

  const sides = [];
  for (let i = 0; i < 6; i++) {
    sides.push({
      value: blockValues[i],     // Block value for this face
      texture: null,
      modifiers: [],
      displayValue: null,
      displayText: `${blockValues[i]}🛡️`  // Display as "X🛡️"
    });
  }

  return {
    type: 'd6-defense',
    sides: sides,
    globalModifiers: [],
    currentRoll: null
  };
}

/**
 * Create a Low Difficulty Enemy D6
 * Sides: 3🛡️, 3🛡️, 2⚔️, 2⚔️, 3⚔️, 3⚔️
 * @returns {Object} Enemy D6 dice object
 */
function createEnemyD6Low() {
  const sides = [
    { value: 3, texture: null, modifiers: [], displayValue: null, displayText: '3🛡️', action: 'defend' },
    { value: 3, texture: null, modifiers: [], displayValue: null, displayText: '3🛡️', action: 'defend' },
    { value: 2, texture: null, modifiers: [], displayValue: null, displayText: '2⚔️', action: 'attack' },
    { value: 2, texture: null, modifiers: [], displayValue: null, displayText: '2⚔️', action: 'attack' },
    { value: 3, texture: null, modifiers: [], displayValue: null, displayText: '3⚔️', action: 'attack' },
    { value: 3, texture: null, modifiers: [], displayValue: null, displayText: '3⚔️', action: 'attack' }
  ];

  return {
    type: 'd6-enemy-low',
    sides: sides,
    globalModifiers: [],
    currentRoll: null
  };
}

/**
 * Create a Medium Difficulty Enemy D6
 * Sides: 5🛡️, 5🛡️, 3⚔️, 3⚔️, 5⚔️, 5⚔️
 * @returns {Object} Enemy D6 dice object
 */
function createEnemyD6Medium() {
  const sides = [
    { value: 5, texture: null, modifiers: [], displayValue: null, displayText: '5🛡️', action: 'defend' },
    { value: 5, texture: null, modifiers: [], displayValue: null, displayText: '5🛡️', action: 'defend' },
    { value: 3, texture: null, modifiers: [], displayValue: null, displayText: '3⚔️', action: 'attack' },
    { value: 3, texture: null, modifiers: [], displayValue: null, displayText: '3⚔️', action: 'attack' },
    { value: 5, texture: null, modifiers: [], displayValue: null, displayText: '5⚔️', action: 'attack' },
    { value: 5, texture: null, modifiers: [], displayValue: null, displayText: '5⚔️', action: 'attack' }
  ];

  return {
    type: 'd6-enemy-medium',
    sides: sides,
    globalModifiers: [],
    currentRoll: null
  };
}

/**
 * Create a High Difficulty Enemy D6
 * Sides: 7🛡️, 7🛡️, 5⚔️, 5⚔️, 7⚔️, 7⚔️
 * @returns {Object} Enemy D6 dice object
 */
function createEnemyD6High() {
  const sides = [
    { value: 7, texture: null, modifiers: [], displayValue: null, displayText: '7🛡️', action: 'defend' },
    { value: 7, texture: null, modifiers: [], displayValue: null, displayText: '7🛡️', action: 'defend' },
    { value: 5, texture: null, modifiers: [], displayValue: null, displayText: '5⚔️', action: 'attack' },
    { value: 5, texture: null, modifiers: [], displayValue: null, displayText: '5⚔️', action: 'attack' },
    { value: 7, texture: null, modifiers: [], displayValue: null, displayText: '7⚔️', action: 'attack' },
    { value: 7, texture: null, modifiers: [], displayValue: null, displayText: '7⚔️', action: 'attack' }
  ];

  return {
    type: 'd6-enemy-high',
    sides: sides,
    globalModifiers: [],
    currentRoll: null
  };
}

/**
 * Create a dice of any size (D6, D8, D12, etc.)
 * @param {number} numSides - Number of sides on the dice
 * @param {string} type - Type identifier (e.g., 'd6', 'd8')
 * @returns {Object} Dice object
 */
function createDice(numSides, type = `d${numSides}`) {
  const sides = [];

  for (let i = 1; i <= numSides; i++) {
    sides.push({
      value: i,
      texture: null,
      modifiers: [],
      displayValue: null
    });
  }

  return {
    type: type,
    sides: sides,
    globalModifiers: [],
    currentRoll: null
  };
}

/**
 * Roll a dice and return the result
 * Takes into account side modifiers and global modifiers
 * @param {Object} dice - The dice object to roll
 * @returns {Object} Roll result with raw value, modifiers, and total
 */
function rollDice(dice) {
  // Get random side (0-indexed)
  const sideIndex = Math.floor(Math.random() * dice.sides.length);
  const side = dice.sides[sideIndex];

  // Get base value (with display override if present)
  const baseValue = side.displayValue !== null ? side.displayValue : side.value;

  // Calculate side-specific modifiers
  let sideModifierTotal = 0;
  if (side.modifiers && side.modifiers.length > 0) {
    sideModifierTotal = side.modifiers.reduce((sum, mod) => sum + (mod.value || 0), 0);
  }

  // Calculate global modifiers
  let globalModifierTotal = 0;
  if (dice.globalModifiers && dice.globalModifiers.length > 0) {
    globalModifierTotal = dice.globalModifiers.reduce((sum, mod) => sum + (mod.value || 0), 0);
  }

  // Calculate total
  const total = baseValue + sideModifierTotal + globalModifierTotal;

  const result = {
    sideIndex: sideIndex,
    baseValue: baseValue,
    sideModifiers: sideModifierTotal,
    globalModifiers: globalModifierTotal,
    total: total,
    side: side
  };

  // Store roll on dice object
  dice.currentRoll = result;

  return result;
}

/**
 * Add a global modifier to a dice (affects all rolls)
 * @param {Object} dice - The dice to modify
 * @param {Object} modifier - Modifier object { name, value, description }
 * @returns {Object} Updated dice
 */
function addGlobalModifier(dice, modifier) {
  dice.globalModifiers.push(modifier);
  return dice;
}

/**
 * Remove a global modifier from a dice
 * @param {Object} dice - The dice to modify
 * @param {string} modifierName - Name of the modifier to remove
 * @returns {Object} Updated dice
 */
function removeGlobalModifier(dice, modifierName) {
  dice.globalModifiers = dice.globalModifiers.filter(mod => mod.name !== modifierName);
  return dice;
}

/**
 * Add a modifier to a specific side of the dice
 * @param {Object} dice - The dice to modify
 * @param {number} sideIndex - Index of the side to modify (0-based)
 * @param {Object} modifier - Modifier object { name, value, description }
 * @returns {Object} Updated dice
 */
function addSideModifier(dice, sideIndex, modifier) {
  if (sideIndex >= 0 && sideIndex < dice.sides.length) {
    dice.sides[sideIndex].modifiers.push(modifier);
  }
  return dice;
}

/**
 * Remove a modifier from a specific side
 * @param {Object} dice - The dice to modify
 * @param {number} sideIndex - Index of the side (0-based)
 * @param {string} modifierName - Name of the modifier to remove
 * @returns {Object} Updated dice
 */
function removeSideModifier(dice, sideIndex, modifierName) {
  if (sideIndex >= 0 && sideIndex < dice.sides.length) {
    dice.sides[sideIndex].modifiers = dice.sides[sideIndex].modifiers.filter(
      mod => mod.name !== modifierName
    );
  }
  return dice;
}

/**
 * Set a custom texture for a specific side
 * @param {Object} dice - The dice to modify
 * @param {number} sideIndex - Index of the side (0-based)
 * @param {string} textureUrl - URL or path to texture image
 * @returns {Object} Updated dice
 */
function setSideTexture(dice, sideIndex, textureUrl) {
  if (sideIndex >= 0 && sideIndex < dice.sides.length) {
    dice.sides[sideIndex].texture = textureUrl;
  }
  return dice;
}

/**
 * Override the display value of a specific side
 * @param {Object} dice - The dice to modify
 * @param {number} sideIndex - Index of the side (0-based)
 * @param {number} displayValue - The value to display/use for this side
 * @returns {Object} Updated dice
 */
function setSideValue(dice, sideIndex, displayValue) {
  if (sideIndex >= 0 && sideIndex < dice.sides.length) {
    dice.sides[sideIndex].displayValue = displayValue;
  }
  return dice;
}

/**
 * Get the total modifier bonus for a dice (sum of all global modifiers)
 * @param {Object} dice - The dice to check
 * @returns {number} Total modifier bonus
 */
function getTotalModifier(dice) {
  return dice.globalModifiers.reduce((sum, mod) => sum + (mod.value || 0), 0);
}

/**
 * Reset a dice to its default state
 * @param {Object} dice - The dice to reset
 * @returns {Object} Reset dice
 */
function resetDice(dice) {
  dice.currentRoll = null;
  dice.globalModifiers = [];

  // Reset all side modifiers and overrides
  dice.sides.forEach(side => {
    side.modifiers = [];
    side.displayValue = null;
    side.texture = null;
  });

  return dice;
}

// Export to global scope
if (typeof window !== 'undefined') {
  window.DiceSystem = {
    createD20,
    createDefenseD6,
    createEnemyD6Low,
    createEnemyD6Medium,
    createEnemyD6High,
    createDice,
    rollDice,
    addGlobalModifier,
    removeGlobalModifier,
    addSideModifier,
    removeSideModifier,
    setSideTexture,
    setSideValue,
    getTotalModifier,
    resetDice
  };
}


// Phase 5: window-exports added for ESM transition (functions/vars called cross-file).
window.createD20 = createD20;
window.createDefenseD6 = createDefenseD6;
window.createDice = createDice;
window.createEnemyD6High = createEnemyD6High;
window.createEnemyD6Low = createEnemyD6Low;
window.createEnemyD6Medium = createEnemyD6Medium;
window.rollDice = rollDice;
