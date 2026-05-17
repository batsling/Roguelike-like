// Auto-generated from Roguelikes.xlsx - Spells

var SPELLS_DATA = [
  {
    "name": "Abyss",
    "cost": 6,
    "rarity": "Rare",
    "description": "Assassinate X, where X is half of the target's Maximum Health",
    "keywords": [],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Assassinate X",
        "value": null,
        "move": "Assassinate",
        "addons": [
          "X"
        ],
        "target": null
      },
      {
        "raw": "where X is half of the target's Maximum Health",
        "value": null,
        "move": "where",
        "addons": [
          "X",
          "is",
          "half",
          "of",
          "the",
          "target's",
          "Maximum",
          "Health"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Abyss.png"
  },
  {
    "name": "Balance",
    "cost": 3,
    "rarity": "Uncommon",
    "description": "1 Magic Dmg Cleave Ranged and Gain 1 Health",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Magic Dmg Cleave Ranged and Gain 1 Health",
        "value": 1,
        "move": "Magic",
        "addons": [
          "Dmg",
          "Cleave",
          "Ranged",
          "and",
          "Gain",
          "1",
          "Health"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Balance.png"
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
        "raw": "Target gains 1 Buffer",
        "value": null,
        "move": "Target",
        "addons": [
          "gains",
          "1",
          "Buffer"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Bind.png"
  },
  {
    "name": "Blaze",
    "cost": 6,
    "rarity": "Rare",
    "description": "13 Magic Dmg Fire Ranged",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "13 Magic Dmg Fire Ranged",
        "value": 13,
        "move": "Magic",
        "addons": [
          "Dmg",
          "Fire",
          "Ranged"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Blaze.png"
  },
  {
    "name": "Burn",
    "cost": 1,
    "rarity": "Uncommon",
    "description": "1 Magic Dmg Fire Ranged Overload",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Magic Dmg Fire Ranged Overload",
        "value": 1,
        "move": "Magic",
        "addons": [
          "Dmg",
          "Fire",
          "Ranged",
          "Overload"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Burn.png"
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
        "raw": "3 Dmg to leftmost and rightmost enemy",
        "value": 3,
        "move": "Dmg",
        "addons": [
          "to",
          "leftmost",
          "and",
          "rightmost",
          "enemy"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Crush.png"
  },
  {
    "name": "Flick",
    "cost": 1,
    "rarity": "Uncommon",
    "description": "1 Magic Dmg Engage Ranged",
    "keywords": [
      "Cooldown"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Magic Dmg Engage Ranged",
        "value": 1,
        "move": "Magic",
        "addons": [
          "Dmg",
          "Engage",
          "Ranged"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Flick.png"
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
        "raw": "Gain +1 Reroll",
        "value": null,
        "move": "Gain",
        "addons": [
          "+1",
          "Reroll"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Gaze.png"
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
        "value": null,
        "move": "Assassinate",
        "addons": [
          "1"
        ],
        "target": null
      },
      {
        "raw": "then Gain 3 mana",
        "value": null,
        "move": "then",
        "addons": [
          "Gain",
          "3",
          "mana"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Harvest.png"
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
        "raw": "Assassinate X",
        "value": null,
        "move": "Assassinate",
        "addons": [
          "X"
        ],
        "target": null
      },
      {
        "raw": "where X is the target's Maximum Health",
        "value": null,
        "move": "where",
        "addons": [
          "X",
          "is",
          "the",
          "target's",
          "Maximum",
          "Health"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Infinity.png"
  },
  {
    "name": "Mend",
    "cost": 2,
    "rarity": "Common",
    "description": "Set friendly target's Health to 10",
    "keywords": [],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Set friendly target's Health to 10",
        "value": null,
        "move": "Set",
        "addons": [
          "friendly",
          "target's",
          "Health",
          "to",
          "10"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Mend.png"
  },
  {
    "name": "Miasma",
    "cost": 3,
    "rarity": "Rare",
    "description": "1 Magic Dmg Poison Ranged Cleave",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Magic Dmg Poison Ranged Cleave",
        "value": 1,
        "move": "Magic",
        "addons": [
          "Dmg",
          "Poison",
          "Ranged",
          "Cleave"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Miasma.png"
  },
  {
    "name": "Poke",
    "cost": 1,
    "rarity": "Common",
    "description": "1 Magic Dmg Ranged",
    "keywords": [
      "Cooldown"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Magic Dmg Ranged",
        "value": 1,
        "move": "Magic",
        "addons": [
          "Dmg",
          "Ranged"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Poke.png"
  },
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
        "raw": "Gain 2 Health",
        "value": null,
        "move": "Gain",
        "addons": [
          "2",
          "Health"
        ],
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
        "raw": "Gain 2 Health and Cleanse 1",
        "value": null,
        "move": "Gain",
        "addons": [
          "2",
          "Health",
          "and",
          "Cleanse",
          "1"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Remedy.png"
  },
  {
    "name": "Scald",
    "cost": 3,
    "rarity": "Uncommon",
    "description": "2 Magic Dmg Water Ranged to all damaged enemies",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "2 Magic Dmg Water Ranged to all damaged enemies",
        "value": 2,
        "move": "Magic",
        "addons": [
          "Dmg",
          "Water",
          "Ranged",
          "to",
          "all",
          "damaged",
          "enemies"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Scald.png"
  },
  {
    "name": "Scorch",
    "cost": 3,
    "rarity": "Common",
    "description": "1 Magic Dmg Fire Cleave Ranged",
    "keywords": [
      "SingleCast"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Magic Dmg Fire Cleave Ranged",
        "value": 1,
        "move": "Magic",
        "addons": [
          "Dmg",
          "Fire",
          "Cleave",
          "Ranged"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Scorch.png"
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
        "raw": "Gain 3 Health",
        "value": null,
        "move": "Gain",
        "addons": [
          "3",
          "Health"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Sprout.png"
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
        "value": null,
        "move": "Assassinate",
        "addons": [
          "2"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Zap.png"
  }
];
