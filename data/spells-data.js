// Auto-generated from Roguelikes.xlsx - Spells

var SPELLS_DATA = [
  {
    "name": "Poultice",
    "cost": 1,
    "rarity": "Common",
    "description": "2 Heal",
    "keywords": [
      "SingleCast"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "2 Heal",
        "value": 2,
        "move": "Heal",
        "addons": [],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Poultice.png"
  },
  {
    "name": "Remedy",
    "cost": 1,
    "rarity": "Common",
    "description": "1 Heal, 1 Cleanse",
    "keywords": [
      "SingleCast"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Heal",
        "value": 1,
        "move": "Heal",
        "addons": [],
        "target": null
      },
      {
        "raw": "1 Cleanse",
        "value": 1,
        "move": "Cleanse",
        "addons": [],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Remedy.png"
  },
  {
    "name": "Sprout",
    "cost": 3,
    "rarity": "Common",
    "description": "3 Heal",
    "keywords": [
      "Channel"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "3 Heal",
        "value": 3,
        "move": "Heal",
        "addons": [],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Sprout.png"
  },
  {
    "name": "Abyss",
    "cost": 5,
    "rarity": "Uncommon",
    "description": "Kill an enemy with half or less health",
    "keywords": [],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Kill an enemy with half or less health",
        "value": null,
        "move": "Kill",
        "addons": [
          "an",
          "enemy",
          "with",
          "half",
          "or",
          "less",
          "health"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Abyss.png"
  },
  {
    "name": "Infinity",
    "cost": 13,
    "rarity": "Rare",
    "description": "Kill an enemy",
    "keywords": [],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Kill an enemy",
        "value": null,
        "move": "Kill",
        "addons": [
          "an",
          "enemy"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Infinity.png"
  },
  {
    "name": "Harvest",
    "cost": 1,
    "rarity": "Rare",
    "description": "Kill an enemy with exactly 1 health, then Gain 3 mana",
    "keywords": [
      "Cooldown"
    ],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Kill an enemy with exactly 1 health",
        "value": null,
        "move": "Kill",
        "addons": [
          "an",
          "enemy",
          "with",
          "exactly",
          "1",
          "health"
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
    "name": "Miasma",
    "cost": 3,
    "rarity": "Rare",
    "description": "1 Dmg Cleave, 1 Poison Cleave",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Dmg Cleave",
        "value": 1,
        "move": "Dmg",
        "addons": [
          "Cleave"
        ],
        "target": null
      },
      {
        "raw": "1 Poison Cleave",
        "value": 1,
        "move": "Poison",
        "addons": [
          "Cleave"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Miasma.png"
  },
  {
    "name": "Scald",
    "cost": 3,
    "rarity": "Uncommon",
    "description": "2 Dmg to all damaged enemies",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "2 Dmg to all damaged enemies",
        "value": 2,
        "move": "Dmg",
        "addons": [
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
    "name": "Blaze",
    "cost": 6,
    "rarity": "Rare",
    "description": "13 Dmg",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "13 Dmg",
        "value": 13,
        "move": "Dmg",
        "addons": [],
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
    "name": "Burn",
    "cost": 1,
    "rarity": "Uncommon",
    "description": "1 Dmg Overload",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Dmg Overload",
        "value": 1,
        "move": "Dmg",
        "addons": [
          "Overload"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Burn.png"
  },
  {
    "name": "Bind",
    "cost": 3,
    "rarity": "Rare",
    "description": "Self/Ally gains 1 Dodge",
    "keywords": [
      "Deplete"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "Self/Ally gains 1 Dodge",
        "value": null,
        "move": "Self/Ally",
        "addons": [
          "gains",
          "1",
          "Dodge"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Bind.png"
  },
  {
    "name": "Poke",
    "cost": 1,
    "rarity": "Common",
    "description": "1 Dmg",
    "keywords": [
      "Cooldown"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Dmg",
        "value": 1,
        "move": "Dmg",
        "addons": [],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Poke.png"
  },
  {
    "name": "Flick",
    "cost": 1,
    "rarity": "Uncommon",
    "description": "1 Dmg Engage",
    "keywords": [
      "Cooldown"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Dmg Engage",
        "value": 1,
        "move": "Dmg",
        "addons": [
          "Engage"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Flick.png"
  },
  {
    "name": "Balance",
    "cost": 3,
    "rarity": "Uncommon",
    "description": "1 Dmg Wide, 1 Heal Wide",
    "keywords": [],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 Dmg Wide",
        "value": 1,
        "move": "Dmg",
        "addons": [
          "Wide"
        ],
        "target": null
      },
      {
        "raw": "1 Heal Wide",
        "value": 1,
        "move": "Heal",
        "addons": [
          "Wide"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Balance.png"
  },
  {
    "name": "Mend",
    "cost": 2,
    "rarity": "Common",
    "description": "Set self/ally to 5 Health",
    "keywords": [],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Set self/ally to 5 Health",
        "value": null,
        "move": "Set",
        "addons": [
          "self/ally",
          "to",
          "5",
          "Health"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Mend.png"
  },
  {
    "name": "Scorch",
    "cost": 2,
    "rarity": "Common",
    "description": "1 dmg Cleave",
    "keywords": [
      "SingleCast"
    ],
    "affectedByBonus": true,
    "effects": [
      {
        "raw": "1 dmg Cleave",
        "value": 1,
        "move": "dmg",
        "addons": [
          "Cleave"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Scorch.png"
  },
  {
    "name": "Zap",
    "cost": 2,
    "rarity": "Uncommon",
    "description": "Kill an enemy with exactly 2 health",
    "keywords": [
      "Cooldown"
    ],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Kill an enemy with exactly 2 health",
        "value": null,
        "move": "Kill",
        "addons": [
          "an",
          "enemy",
          "with",
          "exactly",
          "2",
          "health"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Zap.png"
  },
  {
    "name": "Gaze",
    "cost": 1,
    "rarity": "Common",
    "description": "Gain 1 Reroll",
    "keywords": [
      "Future"
    ],
    "affectedByBonus": false,
    "effects": [
      {
        "raw": "Gain 1 Reroll",
        "value": null,
        "move": "Gain",
        "addons": [
          "1",
          "Reroll"
        ],
        "target": null
      }
    ],
    "imageUrl": "images/Spells/Gaze.png"
  }
];
