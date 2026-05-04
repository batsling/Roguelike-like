// Auto-generated from Roguelikes.xlsx - Spells

var SPELLS_DATA = [
  {
    "name": "Poultice",
    "cost": 2,
    "rarity": "Common",
    "description": "Gain 2 Health",
    "keywords": [
      "SingleCast"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "2 Heal",
        "value": 2,
        "move": "heal",
        "addons": [],
        "element": "earth",
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Poultice.png"
  },
  {
    "name": "Remedy",
    "cost": 2,
    "rarity": "Common",
    "description": "Gain 2 Health and Cleanse 1",
    "keywords": [
      "SingleCast"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "2 Heal",
        "value": 2,
        "move": "heal",
        "addons": [],
        "element": "earth",
        "target": null
      },
      {
        "raw": "1 Cleanse",
        "value": 1,
        "move": "cleanse",
        "addons": [],
        "element": null,
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Remedy.png"
  },
  {
    "name": "Sprout",
    "cost": 4,
    "rarity": "Common",
    "description": "Gain 3 Health",
    "keywords": [
      "Channel"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "3 Heal",
        "value": 3,
        "move": "heal",
        "addons": [],
        "element": "earth",
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Sprout.png"
  },
  {
    "name": "Abyss",
    "cost": 6,
    "rarity": "Rare",
    "description": "Assassinate X, where X is half of the target's Maximum Health",
    "keywords": [],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Assassinate halfMax",
        "value": null,
        "move": "assassinate",
        "addons": [
          "halfMax"
        ],
        "element": "dark",
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Abyss.png"
  },
  {
    "name": "Infinity",
    "cost": 15,
    "rarity": "Rare",
    "description": "Assassinate X, where X is the target's Maximum Health",
    "keywords": [],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Assassinate fullMax",
        "value": null,
        "move": "assassinate",
        "addons": [
          "fullMax"
        ],
        "element": "dark",
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Infinity.png"
  },
  {
    "name": "Harvest",
    "cost": 1,
    "rarity": "Rare",
    "description": "Assassinate 1, then Gain 3 mana",
    "keywords": [
      "Cooldown"
    ],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Assassinate 1",
        "value": 1,
        "move": "assassinate",
        "addons": [],
        "element": "blood",
        "target": null
      },
      {
        "raw": "Gain 3 mana",
        "value": 3,
        "move": "gain",
        "addons": [
          "mana"
        ],
        "element": null,
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Harvest.png"
  },
  {
    "name": "Miasma",
    "cost": 3,
    "rarity": "Rare",
    "description": "1 Magic Dmg Poison Cleave",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Magic Dmg Poison Cleave",
        "value": 1,
        "move": "magic dmg",
        "addons": [
          "Cleave"
        ],
        "element": "poison",
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Miasma.png"
  },
  {
    "name": "Scald",
    "cost": 3,
    "rarity": "Uncommon",
    "description": "2 Magic Dmg Water to all damaged enemies",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "2 Magic Dmg Water DamagedEnemies",
        "value": 2,
        "move": "magic dmg",
        "addons": [
          "DamagedEnemies"
        ],
        "element": "water",
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Scald.png"
  },
  {
    "name": "Blaze",
    "cost": 6,
    "rarity": "Rare",
    "description": "13 Magic Dmg",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "13 Magic Dmg",
        "value": 13,
        "move": "magic dmg",
        "addons": [],
        "element": "fire",
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Blaze.png"
  },
  {
    "name": "Crush",
    "cost": 3,
    "rarity": "Rare",
    "description": "3 Dmg to leftmost and rightmost enemy",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "3 Dmg LeftmostRightmost",
        "value": 3,
        "move": "dmg",
        "addons": [
          "LeftmostRightmost"
        ],
        "element": null,
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Crush.png"
  },
  {
    "name": "Burn",
    "cost": 1,
    "rarity": "Uncommon",
    "description": "1 Magic Dmg Fire Overload",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Magic Dmg Fire Overload",
        "value": 1,
        "move": "magic dmg",
        "addons": [
          "Overload"
        ],
        "element": "fire",
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Burn.png"
  },
  {
    "name": "Bind",
    "cost": 3,
    "rarity": "Rare",
    "description": "Target gains 1 Buffer",
    "keywords": [
      "Deplete"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "Self/Ally gains 1 Buffer",
        "value": null,
        "move": "Self/Ally",
        "addons": [
          "gains",
          "1",
          "Buffer"
        ],
        "element": null,
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Bind.png"
  },
  {
    "name": "Poke",
    "cost": 1,
    "rarity": "Common",
    "description": "1 Magic Dmg",
    "keywords": [
      "Cooldown"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Magic Dmg",
        "value": 1,
        "move": "magic dmg",
        "addons": [],
        "element": null,
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Poke.png"
  },
  {
    "name": "Flick",
    "cost": 1,
    "rarity": "Uncommon",
    "description": "1 Magic Dmg Engage",
    "keywords": [
      "Cooldown"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Magic Dmg Engage",
        "value": 1,
        "move": "magic dmg",
        "addons": [
          "Engage"
        ],
        "element": null,
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Flick.png"
  },
  {
    "name": "Balance",
    "cost": 3,
    "rarity": "Uncommon",
    "description": "1 Magic Dmg Cleave and Gain 1 Health",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Magic Dmg Cleave",
        "value": 1,
        "move": "magic dmg",
        "addons": [
          "Cleave"
        ],
        "element": null,
        "target": null
      },
      {
        "raw": "1 Heal",
        "value": 1,
        "move": "heal",
        "addons": [],
        "element": null,
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Balance.png"
  },
  {
    "name": "Mend",
    "cost": 2,
    "rarity": "Common",
    "description": "Set friendly target's Health to 5",
    "keywords": [],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Set health to 5",
        "value": 5,
        "move": "set",
        "addons": [
          "health"
        ],
        "element": "blood",
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Mend.png"
  },
  {
    "name": "Scorch",
    "cost": 3,
    "rarity": "Common",
    "description": "1 Magic Dmg Fire Cleave",
    "keywords": [
      "SingleCast"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Magic Dmg Fire Cleave",
        "value": 1,
        "move": "magic dmg",
        "addons": [
          "Cleave"
        ],
        "element": "fire",
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Scorch.png"
  },
  {
    "name": "Zap",
    "cost": 2,
    "rarity": "Uncommon",
    "description": "Assassinate 2",
    "keywords": [
      "Cooldown"
    ],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Assassinate 2",
        "value": 2,
        "move": "assassinate",
        "addons": [],
        "element": "electric",
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Zap.png"
  },
  {
    "name": "Gaze",
    "cost": 2,
    "rarity": "Common",
    "description": "Gain +1 Reroll",
    "keywords": [
      "Future"
    ],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Gain 1 Reroll",
        "value": 1,
        "move": "gain",
        "addons": [
          "reroll"
        ],
        "element": null,
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Gaze.png"
  }
];
