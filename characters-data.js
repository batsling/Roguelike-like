// Auto-generated from Roguelikes.xlsx - Characters
// Characters with dice-based combat

var CHARACTERS_DATA = {
  "rodney": {
    "name": "Rodney",
    "game": "Rogue",
    "icon": "images/characters/Icon/Rodney.png",
    "fullImage": "images/characters/Full/Rodney.png",
    "energy": 3,
    "mana": 3,
    "levelUpCondition": "Beat a game without meta progression",
    "levelUpStats": {
      "strength": 0,
      "dexterity": 0,
      "intelligence": 0,
      "charisma": 0,
      "reroll": 0,
      "dash": 0,
      "skip": 0,
      "discovery": 0,
      "fov": 0,
      "luck": 0,
      "random": 2
    },
    "description": "Now I abide here, searching endlessly for the precious Amulet... and finding a thousand horrors.",
    "combatStart": "Dice",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "1 Mana",
            "value": 1,
            "move": "Mana",
            "addons": [],
            "target": null
          }
        ],
        "raw": "1 Mana"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "1 Heal",
            "value": 1,
            "move": "Heal",
            "addons": [],
            "target": null
          }
        ],
        "raw": "1 Heal"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Block",
            "value": 2,
            "move": "Block",
            "addons": [],
            "target": null
          }
        ],
        "raw": "2 Block"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Block",
            "value": 2,
            "move": "Block",
            "addons": [],
            "target": null
          }
        ],
        "raw": "2 Block"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Dmg",
            "value": 2,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "2 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Dmg",
            "value": 2,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "2 Dmg"
      }
    ]
  },
  "isaac": {
    "name": "Isaac",
    "game": "The Binding of Isaac",
    "icon": "images/characters/Icon/Isaac.png",
    "fullImage": "images/characters/Full/Isaac.png",
    "energy": 3,
    "mana": 3,
    "levelUpCondition": "Unlock a new gameplay element",
    "levelUpStats": {
      "strength": 1,
      "dexterity": 0,
      "intelligence": 0,
      "charisma": 0,
      "reroll": 1,
      "dash": 0,
      "skip": 0,
      "discovery": 0,
      "fov": 0,
      "luck": 0,
      "random": 0
    },
    "description": "Who am I?",
    "combatStart": "Dice",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "1 Reroll",
            "value": 1,
            "move": "Reroll",
            "addons": [],
            "target": null
          }
        ],
        "raw": "1 Reroll"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "1 Reroll",
            "value": 1,
            "move": "Reroll",
            "addons": [],
            "target": null
          }
        ],
        "raw": "1 Reroll"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Block",
            "value": 2,
            "move": "Block",
            "addons": [],
            "target": null
          }
        ],
        "raw": "2 Block"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Block",
            "value": 2,
            "move": "Block",
            "addons": [],
            "target": null
          }
        ],
        "raw": "2 Block"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Dmg",
            "value": 2,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "2 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Dmg",
            "value": 2,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "2 Dmg"
      }
    ]
  },
  "zoe": {
    "name": "Zoe",
    "game": "Haste",
    "icon": "images/characters/Icon/Zoe.png",
    "fullImage": "images/characters/Full/Zoe.png",
    "energy": 3,
    "mana": 3,
    "levelUpCondition": "Perfect a Game",
    "levelUpStats": {
      "strength": 1,
      "dexterity": 0,
      "intelligence": 0,
      "charisma": 0,
      "reroll": 0,
      "dash": 1,
      "skip": 0,
      "discovery": 0,
      "fov": 0,
      "luck": 0,
      "random": 0
    },
    "description": "Express Delivery: Arrives with haste, before the world ends.",
    "combatStart": "Dice",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "Get 1 Dodge",
            "value": 1,
            "move": "Get",
            "addons": [],
            "target": "Dodge"
          }
        ],
        "raw": "Get 1 Dodge"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "Get 1 Dodge",
            "value": 1,
            "move": "Get",
            "addons": [],
            "target": "Dodge"
          }
        ],
        "raw": "Get 1 Dodge"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Dmg",
            "value": 2,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "2 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Dmg",
            "value": 2,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "2 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Dmg",
            "value": 2,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "2 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Dmg",
            "value": 2,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "2 Dmg"
      }
    ]
  }
};
