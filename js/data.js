// ===== STATE VARIABLES =====
var games = [];
var items = [];
var inventory = [];
var beatenGames = [];
var selectedPhase2Games = [];
var excludedGames = [];
var rations = 10;
var gold = 0;
var health = 10;
var maxHealth = 10;
var strength = 0;
var dexterity = 0;
var intelligence = 0;
var charisma = 0;
var luck = 0;
var roguePoints = 0;
var reroll = 0;
var dash = 0;
var skip = 0;
var discovery = 0; // Number of item choices when collecting rewards (base 2)
var fov = 0; // Field of View - number of game choices shown (base 3)
var pactConditions = {
  lessHealth: 0,
  moreGames: 0,
  randomGame: 0,
  challengeRun: 0,
};
var startGame = null;
var amuletGame = null;
var events = [];
var enemies = [];
var curses = [];
var encounterHistory = [];

// Bingo State Variables
var bingoGoals = [];
var bingoGrid = Array(9).fill(null); // 3x3 grid stored as flat array
var bingoCompleted = Array(9).fill(false);
var completedBingos = 0;
var bingoReroll = 0;
var bingoSkip = 0;
var bingoFoV = 0;
var bingoDiscovery = 0;
var bingoDash = 0;

// Map Viewer State Variables
var scale = 1;
var translateX = 0;
var translateY = 0;
var isPanning = false;
var startX, startY;
var originalSvgWidth = 0;
var originalSvgHeight = 0;
var markedSvg = null;
var debugMode = false;
var playerMarker = null;
var amuletMarker = null;
var playerImageUrl = 'https://i.imgur.com/4foPqje.png';
var amuletImageUrl = 'https://i.imgur.com/kXiZwZX.png';

// Current combat state
var currentEnemy = null;
var currentRoll = null;

// ===== ENEMY IMAGE HELPER =====
/**
 * Get the local image path for an enemy
 * @param {string} enemyName - Name of the enemy
 * @returns {string} - Path to the enemy image
 */
function getEnemyImagePath(enemyName) {
  if (!enemyName) {
    return 'images/enemies/default.png';
  }

  // Convert enemy name to PascalCase filename format
  // "Stone Golem" -> "StoneGolem.png"
  // "Tainted Pooter" -> "TaintedPooter.png"
  const filename = enemyName
    .split(/[^a-zA-Z0-9]+/)  // Split by non-alphanumeric characters
    .filter(word => word.length > 0)  // Remove empty strings
    .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())  // Capitalize first letter
    .join('');  // Join without spaces

  return `images/enemies/${filename}.png`;
}

// Export globally
window.getEnemyImagePath = getEnemyImagePath;

// ===== GAME STATE =====
var gameState = {
  currentGame: null,
  visitedGames: [],
  availableChoices: [],
  saveName: '',
  gameStarted: false,
  phase: null, // Track current phase: 'selection', 'combat', 'event', 'shop', 'escape'
  health: 10,
  maxHealth: 10,
  gold: 0,
  rations: 10,
  inventory: [],
  activeCurses: [], // Track active curses on player
  cursesTracker: {}, // Track curse progress (e.g., games beaten, spaces chosen)
  beatenGames: [],
  finishedGames: [], // Games completed (beaten)
  totalGamesBeaten: 0, // Track total number of game completions (including duplicates)
  skippedGames: [], // Games skipped
  startGame: null,
  amuletGame: null,
  currentY: 120,
  character: 'rogue',
  escapePhase: false,
  escapeGames: [],
  escapeProgress: 0,
  // Weapon system
  equippedWeapon: null, // Currently equipped weapon object
  weaponLevel: 1, // Current weapon level (1-3)
  shopUpgradesUsed: 0 // Track weapon upgrades used in current shop visit
};

var gameSaves = GameStorage.load(STORAGE_KEYS.SAVED_GAMES, {});

// ===== CHARACTER DATA =====
var PLAYER_CHARACTERS = {};

// ===== DATA LOADING =====
// Data is now loaded directly from embedded JavaScript files (no CORS issues!)

// Load data from embedded variables
function initializeData() {
  console.log('=== INITIALIZING DATA ===');
  console.log('Checking for data variables...');

  // Load from embedded data variables (defined in *-data.js files)
  if (typeof CHARACTERS_DATA !== 'undefined') {
    PLAYER_CHARACTERS = CHARACTERS_DATA;
    console.log('✓ Characters loaded:', Object.keys(PLAYER_CHARACTERS).length);
  } else {
    console.error('✗ CHARACTERS_DATA not found!');
  }

  if (typeof GAMES_DATA !== 'undefined') {
    games = GAMES_DATA;
    console.log('✓ Games loaded:', games.length);
    // Count total connections embedded in games
    const totalConnections = games.reduce((sum, game) => sum + (game.gamesInfluenced ? game.gamesInfluenced.length : 0), 0);
    console.log('✓ Connections embedded in games:', totalConnections);
  } else {
    console.error('✗ GAMES_DATA not found!');
  }

  if (typeof ITEMS_DATA !== 'undefined') {
    items = ITEMS_DATA;
    console.log('✓ Items loaded:', items.length);
  } else {
    console.error('✗ ITEMS_DATA not found!');
  }

  if (typeof ENEMIES_DATA !== 'undefined') {
    enemies = ENEMIES_DATA;
    console.log('✓ Enemies loaded:', enemies.length);
  } else {
    console.error('✗ ENEMIES_DATA not found!');
  }

  if (typeof EVENTS_DATA !== 'undefined') {
    events = EVENTS_DATA;
    console.log('✓ Events loaded:', events.length);
  } else {
    console.error('✗ EVENTS_DATA not found!');
  }

  if (typeof CURSES_DATA !== 'undefined') {
    curses = CURSES_DATA;
    console.log('✓ Curses loaded:', curses.length);
  } else {
    console.error('✗ CURSES_DATA not found!');
  }

  console.log('=== DATA SUMMARY ===');
  console.log('Games:', games.length);
  console.log('Items:', items.length);
  console.log('Events:', events.length);
  console.log('Enemies:', enemies.length);
  console.log('Curses:', curses.length);
  console.log('Characters:', Object.keys(PLAYER_CHARACTERS).length);

  // Populate UI dropdowns if function is available
  setTimeout(() => {
    if (typeof populateGameSelects === 'function') {
      populateGameSelects();
    }
    if (typeof populateItemSelects === 'function') {
      populateItemSelects();
    }
    if (typeof populateCurseSelects === 'function') {
      populateCurseSelects();
    }
    if (typeof populateEnemySelect === 'function') {
      populateEnemySelect();
    }
    if (typeof updateActiveCursesList === 'function') {
      updateActiveCursesList();
    }
  }, 100);
}

// Call initialization when page loads
initializeData();

// ===== LUCK SYSTEM =====

/**
 * Calculate rarity weights based on luck stat
 * Base weights: Common 70, Uncommon 20, Rare 10
 * Each point of Luck: Common -3, Uncommon +2, Rare +1
 * @param {number} luckValue - The player's luck stat
 * @returns {Object} Weights for each rarity tier
 */
function calculateRarityWeights(luckValue) {
  const baseWeights = {
    common: 70,
    uncommon: 20,
    rare: 10
  };

  const luckModifiers = {
    common: -3,
    uncommon: 2,
    rare: 1
  };

  const weights = {
    common: Math.max(1, baseWeights.common + (luckModifiers.common * luckValue)),
    uncommon: baseWeights.uncommon + (luckModifiers.uncommon * luckValue),
    rare: baseWeights.rare + (luckModifiers.rare * luckValue)
  };

  // Ensure no negative weights
  weights.common = Math.max(1, weights.common);
  weights.uncommon = Math.max(0, weights.uncommon);
  weights.rare = Math.max(0, weights.rare);

  return weights;
}

/**
 * Select a random rarity based on weighted probabilities
 * Legendary items have a 1 in 10 chance when rare is selected
 * @param {number} luckValue - The player's luck stat (defaults to global luck variable)
 * @returns {string} Selected rarity ('common', 'uncommon', 'rare', or 'legendary')
 */
function selectRandomRarity(luckValue = luck) {
  const weights = calculateRarityWeights(luckValue);
  const totalWeight = weights.common + weights.uncommon + weights.rare;

  const roll = Math.random() * totalWeight;

  let selectedRarity;
  if (roll < weights.common) {
    selectedRarity = 'common';
  } else if (roll < weights.common + weights.uncommon) {
    selectedRarity = 'uncommon';
  } else {
    selectedRarity = 'rare';
  }

  // If rare was selected, roll for legendary (10% chance)
  if (selectedRarity === 'rare') {
    const legendaryRoll = Math.random();
    if (legendaryRoll < 0.1) {
      selectedRarity = 'legendary';
    }
  }

  return selectedRarity;
}

/**
 * Roll a D20 with luck modifier
 * @param {number} luckBonus - Additional luck bonus (defaults to global luck variable)
 * @returns {Object} Object containing rawRoll, luckBonus, and total
 */
function rollD20WithLuck(luckBonus = luck) {
  const rawRoll = Math.floor(Math.random() * 20) + 1;
  const total = rawRoll + luckBonus;

  return {
    rawRoll: rawRoll,
    luckBonus: luckBonus,
    total: total
  };
}

/**
 * Calculate proc chance with luck modifier
 * Each point of luck adds 5% to the base proc chance
 * @param {number} baseChance - Base proc chance as a percentage (0-100)
 * @param {number} luckValue - The player's luck stat (defaults to global luck variable)
 * @returns {number} Modified proc chance (capped at 100)
 */
function calculateProcChance(baseChance, luckValue = luck) {
  const modifiedChance = baseChance + (luckValue * 5);
  return Math.min(100, modifiedChance);
}

/**
 * Check if a proc triggers based on base chance and luck
 * @param {number} baseChance - Base proc chance as a percentage (0-100)
 * @param {number} luckValue - The player's luck stat (defaults to global luck variable)
 * @returns {boolean} True if proc triggers
 */
function checkProc(baseChance, luckValue = luck) {
  const finalChance = calculateProcChance(baseChance, luckValue);
  return Math.random() * 100 < finalChance;
}

// Export luck system functions to global scope
window.calculateRarityWeights = calculateRarityWeights;
window.selectRandomRarity = selectRandomRarity;
window.rollD20WithLuck = rollD20WithLuck;
window.calculateProcChance = calculateProcChance;
window.checkProc = checkProc;
