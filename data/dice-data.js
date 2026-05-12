// Auto-generated from Roguelikes.xlsx - Dice
// Each entry describes a named die card and its face outcomes.

var DICE_DATA = [
  {
    "name": "Clumsy",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Deal 3 Dmg Melee, Cantrip",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": [
          "cantrip"
        ]
      },
      {
        "face": 2,
        "text": "Take 3 Dmg, Cantrip",
        "isBlank": false,
        "effects": [
          {
            "move": "pain",
            "value": 3,
            "addons": []
          }
        ],
        "addons": [
          "cantrip"
        ]
      },
      {
        "face": 3,
        "text": "Deal 3 Dmg Melee Cleave",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Melee",
              "Cleave"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 4,
        "text": "Deal 3 Dmg Melee Cleave",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Melee",
              "Cleave"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 5,
        "text": "Deal 3 Dmg Melee, Cantrip",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": [
          "cantrip"
        ]
      },
      {
        "face": 6,
        "text": "Take 3 Dmg, Cantrip",
        "isBlank": false,
        "effects": [
          {
            "move": "pain",
            "value": 3,
            "addons": []
          }
        ],
        "addons": [
          "cantrip"
        ]
      }
    ]
  },
  {
    "name": "Dabblest",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Gain +3 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 3,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Deal 12 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 12,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 3,
        "text": "Deal 9 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 9,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 4,
        "text": "Deal 9 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 9,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 5,
        "text": "Gain +15 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 15,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 6,
        "text": "Gain +5 Health",
        "isBlank": false,
        "effects": [
          {
            "move": "heal",
            "value": 5,
            "addons": []
          }
        ],
        "addons": []
      }
    ]
  },
  {
    "name": "Defender",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Gain +9 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 9,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Gain +6 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 6,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 3,
        "text": "Deal 3 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 4,
        "text": "Deal 3 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 5,
        "text": "Gain +3 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 3,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 6,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      }
    ]
  },
  {
    "name": "Druid",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Deal 6 Dmg Melee.  Increase the Dmg of this Side by 3 this combat.",
        "isBlank": false,
        "effects": [],
        "addons": [
          "druid"
        ]
      },
      {
        "face": 2,
        "text": "Gain +6 Block. Increase the Block of this Side by 3 this combat.",
        "isBlank": false,
        "effects": [],
        "addons": [
          "druid"
        ]
      },
      {
        "face": 3,
        "text": "Gain +2 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 2,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 4,
        "text": "Gain +2 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 2,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 5,
        "text": "Gain +2 Health, Cleanse 2",
        "isBlank": false,
        "effects": [
          {
            "move": "heal",
            "value": 2,
            "addons": []
          },
          {
            "move": "cleanse",
            "value": 2,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 6,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      }
    ]
  },
  {
    "name": "Fighter",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Deal 6 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 6,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Deal 6 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 6,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 3,
        "text": "Deal 3 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 4,
        "text": "Deal 3 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 5,
        "text": "Gain +3 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 3,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 6,
        "text": "Gain +3 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 3,
            "addons": []
          }
        ],
        "addons": []
      }
    ]
  },
  {
    "name": "Gambler",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Deal 15 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 15,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Deal 12 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 12,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 3,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      },
      {
        "face": 4,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      },
      {
        "face": 5,
        "text": "Deal 1 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 1,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 6,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      }
    ]
  },
  {
    "name": "Gladiator",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Deal 6 Dmg Melee Engage",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 6,
            "addons": [
              "Melee",
              "Engage"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Deal 3 Dmg Melee Engage",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Melee",
              "Engage"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 3,
        "text": "Deal 6 Dmg Melee, Gain +6 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 6,
            "addons": [
              "Melee"
            ]
          },
          {
            "move": "block",
            "value": 6,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 4,
        "text": "Deal 6 Dmg Melee, Gain +6 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 6,
            "addons": [
              "Melee"
            ]
          },
          {
            "move": "block",
            "value": 6,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 5,
        "text": "Gain +6 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 6,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 6,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      }
    ]
  },
  {
    "name": "Healer",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Gain +2 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 2,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Gain +1 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 1,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 3,
        "text": "Gain +4 Health",
        "isBlank": false,
        "effects": [
          {
            "move": "heal",
            "value": 4,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 4,
        "text": "Gain +4 Health",
        "isBlank": false,
        "effects": [
          {
            "move": "heal",
            "value": 4,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 5,
        "text": "Gain +1 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 1,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 6,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      }
    ]
  },
  {
    "name": "Isaac's D6",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Random Attack, Skill, or Power that is free to play this combat, Mandatory",
        "isBlank": false,
        "isaacsTransform": true,
        "effects": [],
        "addons": ["mandatory"]
      },
      {
        "face": 2,
        "text": "Random Power, Mandatory",
        "isBlank": false,
        "isaacsTransform": true,
        "effects": [],
        "addons": ["mandatory"]
      },
      {
        "face": 3,
        "text": "Random Skill, Mandatory",
        "isBlank": false,
        "isaacsTransform": true,
        "effects": [],
        "addons": ["mandatory"]
      },
      {
        "face": 4,
        "text": "Random Attack, Mandatory",
        "isBlank": false,
        "isaacsTransform": true,
        "effects": [],
        "addons": ["mandatory"]
      },
      {
        "face": 5,
        "text": "Random Status, Mandatory",
        "isBlank": false,
        "isaacsTransform": true,
        "effects": [],
        "addons": ["mandatory"]
      },
      {
        "face": 6,
        "text": "Random Curse, Mandatory",
        "isBlank": false,
        "isaacsTransform": true,
        "effects": [],
        "addons": ["mandatory"]
      }
    ]
  },
  {
    "name": "Jester",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Gain +3 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 3,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Gain +1 Reroll, Cantrip",
        "isBlank": false,
        "effects": [
          {
            "move": "reroll",
            "value": 1,
            "addons": []
          }
        ],
        "addons": [
          "cantrip"
        ]
      },
      {
        "face": 3,
        "text": "Gain +1 Mana, Single Use",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 1,
            "addons": []
          }
        ],
        "addons": [
          "singleUse"
        ]
      },
      {
        "face": 4,
        "text": "Gain +1 Mana, Single Use",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 1,
            "addons": []
          }
        ],
        "addons": [
          "singleUse"
        ]
      },
      {
        "face": 5,
        "text": "Gain +1 Buffer",
        "isBlank": true,
        "effects": [],
        "addons": []
      },
      {
        "face": 6,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      }
    ]
  },
  {
    "name": "Juggler",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Deal 6 Dmg Melee, Cantrip",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 6,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": [
          "cantrip"
        ]
      },
      {
        "face": 2,
        "text": "Deal 6 Dmg Melee, Cantrip",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 6,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": [
          "cantrip"
        ]
      },
      {
        "face": 3,
        "text": "Deal 3 Dmg Melee, Cantrip",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": [
          "cantrip"
        ]
      },
      {
        "face": 4,
        "text": "Deal 3 Dmg Melee, Cantrip",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": [
          "cantrip"
        ]
      },
      {
        "face": 5,
        "text": "Take 3 Dmg, Cantrip",
        "isBlank": false,
        "effects": [
          {
            "move": "pain",
            "value": 3,
            "addons": []
          }
        ],
        "addons": [
          "cantrip"
        ]
      },
      {
        "face": 6,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      }
    ]
  },
  {
    "name": "Lazy",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Deal 12 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 12,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Gain +12 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 12,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 3,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      },
      {
        "face": 4,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      },
      {
        "face": 5,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      },
      {
        "face": 6,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      }
    ]
  },
  {
    "name": "Mage",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Gain +2 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 2,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Gain +2 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 2,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 3,
        "text": "Gain +1 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 1,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 4,
        "text": "Gain +1 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 1,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 5,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      },
      {
        "face": 6,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      }
    ]
  },
  {
    "name": "Mystic",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Gain +3 Block, Gain +1 Health, Gain +1 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 3,
            "addons": []
          },
          {
            "move": "heal",
            "value": 1,
            "addons": []
          },
          {
            "move": "mana",
            "value": 1,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Gain +1 Health, Gain +1 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "heal",
            "value": 1,
            "addons": []
          },
          {
            "move": "mana",
            "value": 1,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 3,
        "text": "Gain +1 Health, Gain +1 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "heal",
            "value": 1,
            "addons": []
          },
          {
            "move": "mana",
            "value": 1,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 4,
        "text": "Gain +1 Health, Gain +1 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "heal",
            "value": 1,
            "addons": []
          },
          {
            "move": "mana",
            "value": 1,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 5,
        "text": "Gain +1 Mana",
        "isBlank": false,
        "effects": [
          {
            "move": "mana",
            "value": 1,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 6,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      }
    ]
  },
  {
    "name": "Ranger",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Deal 6 Dmg Ranged Engage",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 6,
            "addons": [
              "Ranged",
              "Engage"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Deal 3 Dmg Ranged Cleave",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Ranged",
              "Cleave"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 3,
        "text": "Deal 3 Dmg Ranged Cleave",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Ranged",
              "Cleave"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 4,
        "text": "Deal 3 Dmg Ranged Cleave",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 3,
            "addons": [
              "Ranged",
              "Cleave"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 5,
        "text": "Deal 6 Dmg Ranged",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 6,
            "addons": [
              "Ranged"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 6,
        "text": "X",
        "isBlank": true,
        "effects": [],
        "addons": []
      }
    ]
  },
  {
    "name": "Soldier",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Deal 9 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 9,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Deal 9 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 9,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 3,
        "text": "Deal 6 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 6,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 4,
        "text": "Deal 6 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 6,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 5,
        "text": "Gain +6 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 6,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 6,
        "text": "Gain +6 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 6,
            "addons": []
          }
        ],
        "addons": []
      }
    ]
  },
  {
    "name": "Veteran",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Deal 12 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 12,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Deal 12 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 12,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 3,
        "text": "Deal 9 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 9,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 4,
        "text": "Deal 9 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 9,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 5,
        "text": "Gain +9 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 9,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 6,
        "text": "Gain +9 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 9,
            "addons": []
          }
        ],
        "addons": []
      }
    ]
  },
  {
    "name": "Warden",
    "sides": 6,
    "faces": [
      {
        "face": 1,
        "text": "Gain +12 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 12,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 2,
        "text": "Gain +9 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 9,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 3,
        "text": "Deal 6 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 6,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 4,
        "text": "Deal 6 Dmg Melee",
        "isBlank": false,
        "effects": [
          {
            "move": "dmg",
            "value": 6,
            "addons": [
              "Melee"
            ]
          }
        ],
        "addons": []
      },
      {
        "face": 5,
        "text": "Gain +6 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 6,
            "addons": []
          }
        ],
        "addons": []
      },
      {
        "face": 6,
        "text": "Gain +3 Block",
        "isBlank": false,
        "effects": [
          {
            "move": "block",
            "value": 3,
            "addons": []
          }
        ],
        "addons": []
      }
    ]
  }
];
