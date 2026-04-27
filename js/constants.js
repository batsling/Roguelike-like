/**
 * Game Constants - Centralized configuration for easy balancing and maintenance
 * All magic numbers and hard-coded values should be defined here
 */

// ===== GAME BALANCE =====
const GAME_BALANCE = {
  // Initial player stats
  INITIAL_HEALTH: 10,
  INITIAL_MAX_HEALTH: 10,
  INITIAL_GOLD: 0,
  INITIAL_STRENGTH: 0,
  INITIAL_DEXTERITY: 0,
  INITIAL_INTELLIGENCE: 0,
  INITIAL_CHARISMA: 0,
  INITIAL_ATTACK: 0,
  INITIAL_LUCK: 0,

  // Difficulty thresholds
  DIFFICULTY: {
    HIGH: { threshold: 10, damage: 3, rollBonus: 4 },
    MEDIUM: { threshold: 5, damage: 2, rollBonus: 2 },
    LOW: { threshold: 0, damage: 1, rollBonus: 0 }
  },

  // Encounter rates (must sum to 1.0)
  ENCOUNTER_RATES: {
    COMBAT: 0.75,  // 75% chance
    EVENT: 0.15,   // 15% chance
    SHOP: 0.10     // 10% chance
  },

  // Progression
  SHOP_MIN_DISTANCE: 4,  // Shops only spawn at 4+ distance from amulet
  STARTING_ABILITIES: {
    SKIP: 3,
    REROLL: 3,
    DASH: 3
  }
};

// ===== LAYOUT & POSITIONING =====
const LAYOUT = {
  // Node positioning on gameplay screen
  NODE_SPACING: 300,        // Horizontal spacing between nodes
  MAX_NODES_PER_ROW: 4,     // Maximum number of game choices per row
  ROW_SPACING: 150,         // Vertical spacing between rows of choices
  VERTICAL_GAP: 200,        // Gap between current game and next choices
  CENTER_X: 450,            // Center X position of viewport

  // Map modal
  MAP_PADDING: 40,
  MAP_MAX_HEIGHT: '70vh',

  // Game node dimensions
  NODE_WIDTH: 240,
  NODE_HEIGHT: 120,
  NODE_BORDER_RADIUS: 12
};

// ===== UI DIMENSIONS =====
const ICON_SIZES = {
  PLAYER_LARGE: 64,         // Player icon on game nodes
  PLAYER_SMALL: 48,         // Smaller player icon variants
  ENCOUNTER: 26,            // Combat/event/shop icons
  STATUS: 20,               // Status effect icons
  ITEM: 75,                 // Item images in inventory
  ITEM_SMALL: 64,           // Item images in selection
  ENEMY: 80,                // Enemy images
  AMULET_BADGE: 24          // Amulet icon on collection games
};

// ===== COLOR PALETTE =====
const COLORS = {
  // Primary colors
  PRIMARY: '#cc6600',
  SECONDARY: '#ff8800',

  // Status colors
  SUCCESS: '#4CAF50',
  DANGER: '#ff4444',
  WARNING: '#ff9800',
  INFO: '#2196F3',

  // Game colors
  GOLD: '#ffcc66',
  PURPLE: '#9b59b6',
  DARK_BG: '#1a1410',
  BORDER: '#444',

  // Stat colors
  STATS: {
    STRENGTH: '#ff4444',
    DEXTERITY: '#4CAF50',
    INTELLIGENCE: '#3498db',
    CHARISMA: '#9b59b6',
    LUCK: '#ffcc66'
  },

  // Node states
  NODES: {
    CURRENT: '#cc6600',
    CHOICE: '#3a3a3a',
    PAST: '#555',
    AMULET: 'linear-gradient(145deg, #ffdd77, #cc9944)'
  },

  // Arrows
  ARROWS: {
    ACTIVE: '#ffdd00',
    PAST: '#aaa',
    BACKGROUND: 'rgba(100, 100, 100, 0.3)',
    SHORTEST_PATH: '#4CAF50'
  },

  // Overlays
  OVERLAY_DARK: 'rgba(0, 0, 0, 0.3)',
  OVERLAY_LIGHT: 'rgba(255, 255, 255, 0.1)'
};

// ===== STORAGE KEYS =====
const STORAGE_KEYS = {
  GAME_STATE: 'roguelikeState',
  SAVED_GAMES: 'roguelikeGameSaves',
  GAME_STATS: 'gameStats',
  RUN_HISTORY: 'runHistory',
  FISH_STATS: 'fishStats',
  DECK_WINS: 'deckWins',
  NOTE_FOR_YOURSELF: 'noteForYourselfCard'
};

// ===== AVAILABLE DECKS =====
// Each deck filters the card reward pool by tag during a run.
// tagFilter: null means all cards are eligible (Random).
const AVAILABLE_DECKS = [
  {
    id: 'Random',
    name: 'Random',
    image: null,
    tagFilter: null,
    description: 'Cards from any pool may appear as rewards.'
  },
  {
    id: 'Ironclad',
    name: 'Ironclad',
    image: 'images/decks/IroncladDeck.png',
    tagFilter: 'ironclad',
    description: 'Only Ironclad cards appear in combat rewards.'
  },
  {
    id: 'Silent',
    name: 'Silent',
    image: 'images/decks/SilentDeck.png',
    tagFilter: 'silent',
    description: 'Only Silent cards appear in combat rewards.'
  }
];

// ===== GAME PHASES =====
const GAME_PHASES = {
  SELECTION: 'selection',
  COMBAT: 'combat',
  EVENT: 'event',
  SHOP: 'shop',
  ESCAPE: 'escape'
};

// ===== RARITY COLORS =====
const RARITY_COLORS = {
  common: '#888',
  uncommon: '#4CAF50',
  rare: '#2196F3',
  epic: '#9b59b6',
  legendary: '#ff9800'
};

// ===== ANIMATION TIMINGS =====
const ANIMATIONS = {
  SCROLL_DURATION: 1000,      // Viewport scroll duration (ms)
  FADE_DURATION: 300,         // Modal fade in/out (ms)
  NOTIFICATION_DURATION: 3000, // Toast notification duration (ms)
  TOOLTIP_DELAY: 200          // Tooltip show delay (ms)
};

// ===== ARROW CONFIGURATION =====
const ARROW_CONFIG = {
  // CSS Arrow settings
  CSS: {
    WIDTH: 8,
    DASHED_GAP: '12px',
    ARROWHEAD_SIZE: 10,
    ARROWHEAD_PROPORTION: 0.8,
    Z_INDEX: 0
  },

  // SVG Arrow settings
  SVG: {
    MARKER_WIDTH: 10,
    MARKER_HEIGHT: 10,
    MARKER_REF_X: 9,
    MARKER_REF_Y: 5
  }
};

// ===== BUTTON Z-INDEX =====
const Z_INDEX = {
  BACKGROUND: 0,
  ARROWS: 0,
  GAME_NODES: 2,
  BUTTONS: 100,
  MODAL: 1000,
  TOOLTIP: 2000
};

// ===== COMBAT SETTINGS =====
const COMBAT = {
  // Dice rolls
  MIN_ROLL: 1,
  MAX_ROLL: 20,
  CRITICAL_SUCCESS: 20,
  CRITICAL_FAILURE: 1,

  // Stone Golem
  STONE_GOLEM: {
    DAMAGE: 2,
    GOLD_REWARD: 10,
    TOTAL_FIGHTS: 3
  }
};

// ===== CURSE SETTINGS =====
const CURSE_CONFIG = {
  // Curse power damage values
  DAMAGE: {
    1: 1,
    2: 2,
    3: 3,
    4: 4
  },

  // Curse of Shroud configuration
  SHROUD: {
    BASE_CHOICES: 4,      // Base number of choices
    STINKY_GAMES: 2       // Number of "stinky" choices (non-connections)
  }
};

// ===== EVENT CONFIGURATION =====
const EVENT_CONFIG = {
  WILD_MUNCHER: {
    GOLD_COST: 10,
    ITEMS_GAINED: 2
  },

  COLOSSEUM: {
    SUCCESS_ITEMS: 2,
    FAILURE_DAMAGE: 3
  }
};

// ===== SHOP CONFIGURATION =====
const SHOP_CONFIG = {
  NUM_ITEMS: 3,          // Number of items in shop
  REROLL_COST: 5,        // Gold cost to reroll shop
  MAX_REROLLS: 3         // Maximum number of rerolls
};

// Export all constants
if (typeof window !== 'undefined') {
  window.GAME_BALANCE = GAME_BALANCE;
  window.LAYOUT = LAYOUT;
  window.ICON_SIZES = ICON_SIZES;
  window.COLORS = COLORS;
  window.STORAGE_KEYS = STORAGE_KEYS;
  window.AVAILABLE_DECKS = AVAILABLE_DECKS;
  window.GAME_PHASES = GAME_PHASES;
  window.RARITY_COLORS = RARITY_COLORS;
  window.ANIMATIONS = ANIMATIONS;
  window.ARROW_CONFIG = ARROW_CONFIG;
  window.Z_INDEX = Z_INDEX;
  window.COMBAT = COMBAT;
  window.CURSE_CONFIG = CURSE_CONFIG;
  window.EVENT_CONFIG = EVENT_CONFIG;
  window.SHOP_CONFIG = SHOP_CONFIG;
}
