// ===== STATE VARIABLES =====
var games = [];
var connections = [];
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
var discovery = 2; // Number of item choices when collecting rewards
var fov = 3; // Field of View - number of game choices shown
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

// ===== GAME STATE =====
var gameState = {
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
  activeCurses: [], // Track active curses on player
  cursesTracker: {}, // Track curse progress (e.g., games beaten, spaces chosen)
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

var gameSaves = JSON.parse(localStorage.getItem('roguelikeGameSaves') || '{}');

// ===== CHARACTER DATA =====
var PLAYER_CHARACTERS = {};

// ===== DATA LOADING =====
// Data is now loaded directly from embedded JavaScript files (no CORS issues!)

// Load data from embedded variables
function initializeData() {
  // Load from embedded data variables (defined in *-data.js files)
  if (typeof CHARACTERS_DATA !== 'undefined') {
    PLAYER_CHARACTERS = CHARACTERS_DATA;
    console.log('Characters loaded:', Object.keys(PLAYER_CHARACTERS).length);
  }

  if (typeof GAMES_DATA !== 'undefined') {
    games = GAMES_DATA;
    console.log('Games loaded:', games.length);
  }

  if (typeof CONNECTIONS_DATA !== 'undefined') {
    connections = CONNECTIONS_DATA;
    console.log('Connections loaded:', connections.length);
  }

  if (typeof ITEMS_DATA !== 'undefined') {
    items = ITEMS_DATA;
    console.log('Items loaded:', items.length);
  }

  if (typeof ENEMIES_DATA !== 'undefined') {
    enemies = ENEMIES_DATA;
    console.log('Enemies loaded:', enemies.length);
  }

  if (typeof EVENTS_DATA !== 'undefined') {
    events = EVENTS_DATA;
    console.log('Events loaded:', events.length);
  }

  if (typeof CURSES_DATA !== 'undefined') {
    curses = CURSES_DATA;
    console.log('Curses loaded:', curses.length);
  }

  console.log('All data loaded successfully!');
  console.log('- Games:', games.length);
  console.log('- Connections:', connections.length);
  console.log('- Items:', items.length);
  console.log('- Events:', events.length);
  console.log('- Enemies:', enemies.length);
  console.log('- Curses:', curses.length);

  // Populate UI dropdowns if function is available
  setTimeout(() => {
    if (typeof populateGameSelects === 'function') {
      populateGameSelects();
    }
    if (typeof populateItemSelects === 'function') {
      populateItemSelects();
    }
  }, 100);
}

// Call initialization when page loads
initializeData();
