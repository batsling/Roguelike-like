// ===== STATE VARIABLES =====
let games = [];
let connections = [];
let items = [];
let inventory = [];
let beatenGames = [];
let selectedPhase2Games = [];
let excludedGames = [];
let rations = 10;
let gold = 0;
let health = 10;
let maxHealth = 10;
let strength = 0;
let dexterity = 0;
let intelligence = 0;
let charisma = 0;
let luck = 0;
let roguePoints = 0;
let reroll = 0;
let dash = 0;
let skip = 0;
let discovery = 2; // Number of item choices when collecting rewards
let fov = 3; // Field of View - number of game choices shown
let pactConditions = {
  lessHealth: 0,
  moreGames: 0,
  randomGame: 0,
  challengeRun: 0,
};
let startGame = null;
let amuletGame = null;
let events = [];
let enemies = [];
let curses = [];
let encounterHistory = [];

// Map Viewer State Variables
let scale = 1;
let translateX = 0;
let translateY = 0;
let isPanning = false;
let startX, startY;
let originalSvgWidth = 0;
let originalSvgHeight = 0;
let markedSvg = null;
let debugMode = false;
let playerMarker = null;
let amuletMarker = null;
const playerImageUrl = 'https://i.imgur.com/4foPqje.png';
const amuletImageUrl = 'https://i.imgur.com/kXiZwZX.png';

// Current combat state
let currentEnemy = null;
let currentRoll = null;

// ===== GAME STATE =====
let gameState = {
  currentGame: null,
  visitedGames: [],
  availableChoices: [],
  saveName: '',
  gameStarted: false,
  health: 10,
  maxHealth: 10,
  gold: 0,
  rations: 10,
  inventory: [],
  beatenGames: [],
  finishedGames: [], // Games completed (beaten)
  skippedGames: [], // Games skipped
  startGame: null,
  amuletGame: null,
  currentY: 120,
  character: 'rogue',
  escapePhase: false,
  escapeGames: [],
  escapeProgress: 0
};

let gameSaves = JSON.parse(localStorage.getItem('roguelikeGameSaves') || '{}');

// ===== CHARACTER DATA =====
let PLAYER_CHARACTERS = {};

// ===== DATA LOADING =====

// Load character data from JSON
async function loadCharacters() {
  try {
    const response = await fetch('data/characters.json');
    PLAYER_CHARACTERS = await response.json();
    console.log('Characters loaded:', Object.keys(PLAYER_CHARACTERS).length);
  } catch (error) {
    console.error('Error loading characters:', error);
    // Fallback to default characters
    PLAYER_CHARACTERS = {
      "rogue": {
        name: "Rodney",
        icon: "https://i.imgur.com/4foPqje.png",
        startingStats: {
          strength: 0,
          dexterity: 2,
          intelligence: 1,
          charisma: 0,
          reroll: 1,
          dash: 1,
          skip: 1,
          discovery: 2
        },
        description: "Swift and cunning, favors dexterity"
      },
      "warrior": {
        name: "The Warrior",
        icon: "https://i.imgur.com/4foPqje.png",
        startingStats: {
          strength: 2,
          dexterity: 0,
          intelligence: 0,
          charisma: 1,
          reroll: 0,
          dash: 1,
          skip: 0,
          discovery: 2
        },
        description: "Strong and brave, favors strength"
      },
      "mage": {
        name: "The Mage",
        icon: "https://i.imgur.com/4foPqje.png",
        startingStats: {
          strength: 0,
          dexterity: 0,
          intelligence: 2,
          charisma: 1,
          reroll: 1,
          dash: 0,
          skip: 0,
          discovery: 3
        },
        description: "Wise and mystical, favors intelligence"
      },
      "bard": {
        name: "The Bard",
        icon: "https://i.imgur.com/4foPqje.png",
        startingStats: {
          strength: 0,
          dexterity: 1,
          intelligence: 0,
          charisma: 2,
          reroll: 0,
          dash: 1,
          skip: 1,
          discovery: 2
        },
        description: "Charming and persuasive, favors charisma"
      }
    };
  }
}

// Load items from JSON (optional - can still use Excel)
async function loadItems() {
  try {
    const response = await fetch('data/items.json');
    const jsonItems = await response.json();
    if (items.length === 0) { // Only use if no Excel data loaded
      items = jsonItems;
      console.log('Items loaded from JSON:', items.length);
    }
  } catch (error) {
    console.log('No items.json found or error loading:', error.message);
  }
}

// Load enemies from JSON (optional - can still use Excel)
async function loadEnemies() {
  try {
    const response = await fetch('data/enemies.json');
    const jsonEnemies = await response.json();
    if (enemies.length === 0) {
      enemies = jsonEnemies;
      console.log('Enemies loaded from JSON:', enemies.length);
    }
  } catch (error) {
    console.log('No enemies.json found or error loading:', error.message);
  }
}

// Load events from JSON (optional - can still use Excel)
async function loadEvents() {
  try {
    const response = await fetch('data/events.json');
    const jsonEvents = await response.json();
    if (events.length === 0) {
      events = jsonEvents;
      console.log('Events loaded from JSON:', events.length);
    }
  } catch (error) {
    console.log('No events.json found or error loading:', error.message);
  }
}

// Load curses from JSON (optional - can still use Excel)
async function loadCurses() {
  try {
    const response = await fetch('data/curses.json');
    const jsonCurses = await response.json();
    if (curses.length === 0) {
      curses = jsonCurses;
      console.log('Curses loaded from JSON:', curses.length);
    }
  } catch (error) {
    console.log('No curses.json found or error loading:', error.message);
  }
}

// Initialize all data
async function initializeData() {
  await loadCharacters();
  // These are optional - Excel can override them
  await loadItems();
  await loadEnemies();
  await loadEvents();
  await loadCurses();
}

// Call initialization when page loads
initializeData();
