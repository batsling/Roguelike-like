// Characters data - loaded directly as JavaScript to avoid CORS issues
var CHARACTERS_DATA = {
  "rodney": {
    "name": "Rodney",
    "icon": "images/characters/icon/rodney.png",
    "fullImage": "images/characters/full/rodney.png",
    "startingStats": {
      "strength": 0,
      "dexterity": 2,
      "intelligence": 1,
      "charisma": 0,
      "reroll": 0,
      "dash": 0,
      "skip": 0,
      "discovery": 0,
      "fov": 0,
      "luck": 0
    },
    "traits": ["regeneration"],
    "description": "Now I abide here, searching endlessly for the precious Amulet... and finding a thousand horrors."
  },
  "isaac": {
    "name": "Isaac",
    "icon": "images/characters/icon/isaac.png",
    "fullImage": "images/characters/full/isaac.png",
    "startingStats": {
      "strength": 3,
      "dexterity": 0,
      "intelligence": 0,
      "charisma": 0,
      "reroll": 0,
      "dash": 0,
      "skip": 0,
      "discovery": 0,
      "fov": 0,
      "luck": 0
    },
    "traits": ["reroller"],
    "description": "Who am I?"
  },
  "zoe": {
    "name": "Zoe",
    "icon": "images/characters/icon/zoe.png",
    "fullImage": "images/characters/full/zoe.png",
    "startingStats": {
      "strength": 2,
      "dexterity": 0,
      "intelligence": 0,
      "charisma": 0,
      "reroll": 0,
      "dash": 1,
      "skip": 0,
      "discovery": 0,
      "fov": 0,
      "luck": 0
    },
    "traits": ["perfect_precision"],
    "description": "Express Delivery: Arrives with haste, before the world ends."
  }
};

// Trait definitions
var TRAITS_DATA = {
  "reroller": {
    "name": "Reroller",
    "description": "Every time you beat a game, gain +1 Reroll",
    "icon": "🎲"
  },
  "regeneration": {
    "name": "Regeneration",
    "description": "Every time you choose a game whose encounter isn't enemy combat, heal +1",
    "icon": "💚"
  },
  "perfect_precision": {
    "name": "Perfect Precision",
    "description": "Every time you beat a game without losing a run, gain +1 Dash",
    "icon": "🎯"
  }
};
