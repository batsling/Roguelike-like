// ===== STATE VARIABLES =====
var games = [];
var items = [];
var inventory = [];
var beatenGames = [];
var selectedPhase2Games = [];
var excludedGames = [];
var gold = 0;
var health = 10;
var maxHealth = 10;
var strength = 0;
var dexterity = 0;
var intelligence = 0;
var charisma = 0;
var attack = 0;
var luck = 0;
var reroll = 0;
var dash = 0;
var skip = 0;
var discovery = 0; // Number of item choices when collecting rewards (base 2)
var fov = 0; // Field of View - number of game choices shown (base 3)
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

// Card system state
var cards = []; // All available cards data (CARDS_DATA)

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
  energy: 2, // Energy available per turn in combat
  maxEnergy: 2, // Maximum energy per turn (can be increased by items)
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
  // Card/Deck system
  deck: [],        // All cards the player owns (persistent)
  hand: [],        // Cards currently in hand during combat
  drawPile: [],    // Cards left to draw from this combat
  discardPile: [], // Cards played this combat
  // Combat encounter tracking (for weight-based system)
  totalCombatsCompleted: 0,   // How many combats have been completed this run
  lastDifficultyTier: null,   // 'Low', 'Medium', 'High' - tracks transitions
  // Difficulty battery (Insane tier overheat tracking)
  insaneBatteryFills: 0,      // How many times the Insane battery has fully filled
  // Shop per-visit services
  shopUpgradesUsed: 0,        // Card upgrade used this shop visit (max 1)
  shopRemovesUsed: 0,         // Card remove used this shop visit (max 1)
  cardsRemovedThisRun: 0,     // Total removals this run (used to scale removal cost)
  diceSlots: {},              // { [dieUid]: item | null } — items slotted onto dice
  // Node detail system: pre-generated data per choice node
  // { [gameName]: { enemies: Enemy[], postCombatOptions: string[] } }
  choiceDetails: {}
};

var gameSaves = GameStorage.load(STORAGE_KEYS.SAVED_GAMES, {});

// ===== CHARACTER DATA =====
var PLAYER_CHARACTERS = {};

// ===== DATA LOADING =====
// Data is now loaded directly from embedded JavaScript files (no CORS issues!)

// Load data from embedded variables
function initializeData() {

  // Load from embedded data variables (defined in *-data.js files)
  if (typeof CHARACTERS_DATA !== 'undefined') {
    // Convert array to object keyed by name and add image paths
    PLAYER_CHARACTERS = {};
    Object.values(CHARACTERS_DATA).forEach(char => {
      PLAYER_CHARACTERS[char.name] = {
        ...char,
        icon: `images/characters/Icon/${char.name}.png`,
        fullImage: `images/characters/Full/${char.name}.png`
      };
    });
  } else {
    console.error('✗ CHARACTERS_DATA not found!');
  }

  if (typeof GAMES_DATA !== 'undefined') {
    games = GAMES_DATA;
    // Count total connections embedded in games
    const totalConnections = games.reduce((sum, game) => sum + (game.gamesInfluenced ? game.gamesInfluenced.length : 0), 0);
  } else {
    console.error('✗ GAMES_DATA not found!');
  }

  if (typeof ITEMS_DATA !== 'undefined') {
    items = ITEMS_DATA.slice();
    // Merge weapons into item pool so they can appear in chests/loot
    if (typeof WEAPONS_DATA !== 'undefined') {
      WEAPONS_DATA.forEach(w => {
        if (!items.find(i => i.name === w.name)) {
          items.push({
            name: w.name,
            rarity: w.rarity,
            type: 'Weapon',
            description: w.upgradeEffect || '',
            image: w.imageUrl,
            reference: w.game,
            tags: w.tags || [],
          });
        }
      });
    }
  } else {
    console.error('✗ ITEMS_DATA not found!');
  }

  if (typeof ENEMIES_DATA !== 'undefined') {
    enemies = ENEMIES_DATA;
  } else {
    console.error('✗ ENEMIES_DATA not found!');
  }

  if (typeof EVENTS_DATA !== 'undefined') {
    events = EVENTS_DATA;
  } else {
    console.error('✗ EVENTS_DATA not found!');
  }

  if (typeof CURSES_DATA !== 'undefined') {
    curses = CURSES_DATA;
  } else {
    console.error('✗ CURSES_DATA not found!');
  }

  // New dice combat data
  if (typeof ALLIES_DATA !== 'undefined') {
  } else {
    console.warn('✗ ALLIES_DATA not found (optional for dice combat)');
  }

  if (typeof WEAPONS_DATA !== 'undefined') {
  } else {
    console.warn('✗ WEAPONS_DATA not found (optional for dice combat)');
  }

  if (typeof CARDS_DATA !== 'undefined') {
    cards = CARDS_DATA;
  } else {
    console.warn('✗ CARDS_DATA not found');
  }

  if (typeof STATUSES_DATA !== 'undefined') {
  }

  if (typeof MOVES_DATA !== 'undefined') {
  }

  if (typeof SPELLS_DATA !== 'undefined') {
  }


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
 * Roll a uniform [0,1) value with optional luck-based advantage.
 * Each luck point gives a 10% independent chance to grant advantage.
 *
 * favorHigh = true  (default): take the MAX of two rolls.
 *   Use for avoidance/rarity — higher roll → harder to fall below a bad threshold,
 *   more likely to land in uncommon/rare buckets.
 *
 * favorHigh = false: take the MIN of two rolls.
 *   Use for procs/triggers — lower roll → more likely to fall below a proc threshold.
 *
 * @param {number} [luckVal] - Player luck (defaults to global `luck`)
 * @param {boolean} [favorHigh=true]
 * @returns {number} A value in [0,1)
 */
function rollWithLuckAdvantage(luckVal, favorHigh = true) {
  const lv = (luckVal !== undefined) ? luckVal : (typeof luck !== 'undefined' ? luck : 0);
  const r = Math.random();
  if (lv > 0 && Math.random() < lv * 0.1) {
    const r2 = Math.random();
    return favorHigh ? Math.max(r, r2) : Math.min(r, r2);
  }
  if (lv < 0 && Math.random() < Math.abs(lv) * 0.1) {
    const r2 = Math.random();
    // disadvantage flips the preference
    return favorHigh ? Math.min(r, r2) : Math.max(r, r2);
  }
  return r;
}

/**
 * Base rarity weights — Common 70, Uncommon 20, Rare 10.
 * Luck no longer shifts the weights directly; instead it grants advantage
 * on the roll inside selectRandomRarity, biasing toward higher-value buckets.
 */
function calculateRarityWeights() {
  return { common: 75, uncommon: 20, rare: 5 };
}

/**
 * Select a random rarity.
 * Base: Common 70%, Uncommon 20%, Rare 10%.
 * Luck advantage (10% per luck point) biases the roll toward uncommon/rare.
 * Legendary items have a 1-in-10 chance when rare is selected.
 *
 * @param {number} [luckVal] - Player luck (defaults to global `luck`)
 * @returns {string} 'common' | 'uncommon' | 'rare' | 'legendary'
 */
function selectRandomRarity(luckVal) {
  const weights = calculateRarityWeights();
  const totalWeight = weights.common + weights.uncommon + weights.rare;

  // Higher roll → more likely to land in uncommon/rare bucket
  const roll = rollWithLuckAdvantage(luckVal) * totalWeight;

  let selectedRarity;
  if (roll < weights.common) {
    selectedRarity = 'common';
  } else if (roll < weights.common + weights.uncommon) {
    selectedRarity = 'uncommon';
  } else {
    selectedRarity = 'rare';
  }

  if (selectedRarity === 'rare' && Math.random() < 0.1) {
    selectedRarity = 'legendary';
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
 * Returns the base proc chance unchanged — luck is handled by rollWithLuckAdvantage.
 * Kept for backward compatibility.
 */
function calculateProcChance(baseChance) {
  return baseChance;
}

/**
 * Check if a proc triggers. Luck grants advantage (MIN roll), making procs more likely.
 * @param {number} baseChance - Base proc chance as a percentage (0-100)
 * @param {number} [luckVal] - Player luck (defaults to global `luck`)
 * @returns {boolean} True if proc triggers
 */
function checkProc(baseChance, luckVal) {
  return rollWithLuckAdvantage(luckVal, false) * 100 < baseChance;
}

// Export luck system functions to global scope
window.rollWithLuckAdvantage = rollWithLuckAdvantage;
window.calculateRarityWeights = calculateRarityWeights;
window.selectRandomRarity = selectRandomRarity;
window.rollD20WithLuck = rollD20WithLuck;
window.calculateProcChance = calculateProcChance;
window.checkProc = checkProc;
