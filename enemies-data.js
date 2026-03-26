// Auto-generated from Roguelikes.xlsx - Enemies
// Enemies with dice-based combat

var ENEMIES_DATA = [
  {
    "name": "Lemurian",
    "type": "Strength",
    "difficulty": "Low",
    "weight": 1,
    "hpMin": 30,
    "hpMax": 34,
    "ability": "Stagger 33%",
    "pattern": "Always: 75% 6 Dmg Ranged 1 Burn / 25% 9 Dmg Melee",
    "game": "Risk of Rain",
    "location": "General",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "Get 1 Power",
            "value": 1,
            "move": "Get",
            "addons": [],
            "target": "Power"
          }
        ],
        "raw": "Get 1 Power"
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
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      }
    ],
    "imageUrl": "images/enemies/Lemurian.png",
    "variantOf": null
  },
  {
    "name": "Stone Golem",
    "type": "Strength",
    "difficulty": "Medium",
    "weight": 2,
    "hpMin": 64,
    "hpMax": 70,
    "ability": "Stagger 33%",
    "pattern": "Turn 1: Unknown Intent (\"Charging\") | Turn 2: 50% 10 Dmg Ranged / 50% 7 Dmg Melee 2 Vulnerable | Next: Repeat",
    "game": "Risk of Rain",
    "location": "General",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "Get 2 Power",
            "value": 2,
            "move": "Get",
            "addons": [],
            "target": "Power"
          }
        ],
        "raw": "Get 2 Power"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg"
      }
    ],
    "imageUrl": "images/enemies/StoneGolem.png",
    "variantOf": null
  },
  {
    "name": "Elder Lemurian",
    "type": "Strength",
    "difficulty": "High",
    "weight": 7,
    "hpMin": 200,
    "hpMax": 220,
    "ability": "Stagger 33%",
    "pattern": "Always: 50% 3x5 Dmg Ranged / 50% 8 Dmg Melee 5 Burn",
    "game": "Risk of Rain",
    "location": "General",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "Get 2 Power",
            "value": 2,
            "move": "Get",
            "addons": [],
            "target": "Power"
          }
        ],
        "raw": "Get 2 Power"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "5 Dmg",
            "value": 5,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "5 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "7 Dmg",
            "value": 7,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "3 Burn",
            "value": 3,
            "move": "Burn",
            "addons": [],
            "target": null
          }
        ],
        "raw": "7 Dmg, 3 Burn"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "7 Dmg",
            "value": 7,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "3 Burn",
            "value": 3,
            "move": "Burn",
            "addons": [],
            "target": null
          }
        ],
        "raw": "7 Dmg, 3 Burn"
      }
    ],
    "imageUrl": "images/enemies/ElderLemurian.png",
    "variantOf": null
  },
  {
    "name": "Pacer",
    "type": "Strength",
    "difficulty": null,
    "weight": null,
    "hpMin": 20,
    "hpMax": 24,
    "ability": "N/A",
    "pattern": "Always: 75% Unknown Intent (\"Wandering\") / 25% 6 Dmg Melee",
    "game": "The Binding of Isaac",
    "location": "General",
    "dice": [
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
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      }
    ],
    "imageUrl": "images/enemies/Pacer.png",
    "variantOf": null
  },
  {
    "name": "Gaper",
    "type": "Strength",
    "difficulty": "Low",
    "weight": 1,
    "hpMin": 20,
    "hpMax": 24,
    "ability": "When Defeated, 60% Spawn Pacer / 40% Spawn Gusher",
    "pattern": "Always: 6 Dmg Melee",
    "game": "The Binding of Isaac",
    "location": "General",
    "dice": [
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
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      }
    ],
    "imageUrl": "images/enemies/Gaper.png",
    "variantOf": null
  },
  {
    "name": "Gusher",
    "type": "Strength",
    "difficulty": null,
    "weight": null,
    "hpMin": 20,
    "hpMax": 24,
    "ability": "N/A",
    "pattern": "Always: 75% Unknown Intent (\"Wandering\") / 25% 6 Dmg Ranged",
    "game": "The Binding of Isaac",
    "location": "General",
    "dice": [
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      }
    ],
    "imageUrl": "images/enemies/Gusher.png",
    "variantOf": null
  },
  {
    "name": "Double Vis",
    "type": "Strength",
    "difficulty": "Medium",
    "weight": 3,
    "hpMin": 48,
    "hpMax": 54,
    "ability": "N/A",
    "pattern": "Always: 10 Dmg Overload Ranged",
    "game": "The Binding of Isaac",
    "location": "General",
    "dice": [
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "5 Dmg Overload",
            "value": 5,
            "move": "Dmg",
            "addons": [
              "Overload"
            ],
            "target": null
          }
        ],
        "raw": "5 Dmg Overload"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "5 Dmg Overload",
            "value": 5,
            "move": "Dmg",
            "addons": [
              "Overload"
            ],
            "target": null
          }
        ],
        "raw": "5 Dmg Overload"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "5 Dmg Overload",
            "value": 5,
            "move": "Dmg",
            "addons": [
              "Overload"
            ],
            "target": null
          }
        ],
        "raw": "5 Dmg Overload"
      }
    ],
    "imageUrl": "images/enemies/DoubleVis.png",
    "variantOf": null
  },
  {
    "name": "Tainted Pooter",
    "type": "Strength",
    "difficulty": "High",
    "weight": 7,
    "hpMin": 130,
    "hpMax": 140,
    "ability": "When Defeated, Strength Save 15 or take 3 Dmg",
    "pattern": "Turn 1: 5x4 Dmg Ranged | Turn 2: 5x2 Dmg Ranged",
    "game": "The Binding of Isaac",
    "location": "General",
    "dice": [
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg Cleave",
            "value": 3,
            "move": "Dmg",
            "addons": [
              "Cleave"
            ],
            "target": null
          }
        ],
        "raw": "3 Dmg Cleave"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg Cleave",
            "value": 3,
            "move": "Dmg",
            "addons": [
              "Cleave"
            ],
            "target": null
          }
        ],
        "raw": "3 Dmg Cleave"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "6 Dmg Cleave",
            "value": 6,
            "move": "Dmg",
            "addons": [
              "Cleave"
            ],
            "target": null
          }
        ],
        "raw": "6 Dmg Cleave"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "6 Dmg Cleave",
            "value": 6,
            "move": "Dmg",
            "addons": [
              "Cleave"
            ],
            "target": null
          }
        ],
        "raw": "6 Dmg Cleave"
      }
    ],
    "imageUrl": "images/enemies/TaintedPooter.png",
    "variantOf": null
  },
  {
    "name": "Mung",
    "type": "Intelligence",
    "difficulty": null,
    "weight": 1,
    "hpMin": 20,
    "hpMax": 24,
    "ability": "Pigment Rich",
    "pattern": "Always: 50% 3 Dmg Melee / 50% Add 1 random Pigment Status card to your deck",
    "game": "Brutal Orchestra",
    "location": "Desert",
    "dice": [
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "1 Dmg",
            "value": 1,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "1 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "1 Dmg",
            "value": 1,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "1 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "1 Dmg",
            "value": 1,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "1 Dmg"
      }
    ],
    "imageUrl": "images/enemies/Mung.png",
    "variantOf": null
  },
  {
    "name": "Mud Lung",
    "type": "Intelligence",
    "difficulty": "Low",
    "weight": 2,
    "hpMin": 30,
    "hpMax": 34,
    "ability": "Pigment Rich",
    "pattern": "Always: 58% 6 Dmg Melee / 42% Consume 1 random Pigment Status card in Any for 3 Power, 6 Block",
    "game": "Brutal Orchestra",
    "location": "Desert",
    "dice": [
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      }
    ],
    "imageUrl": "images/enemies/MudLung.png",
    "variantOf": null
  },
  {
    "name": "Mungling Mud Lung",
    "type": "Intelligence",
    "difficulty": "Low",
    "weight": 3,
    "hpMin": 48,
    "hpMax": 54,
    "ability": "Pigment Rich / Multi Attack 2 / When Defeated, 50% chance to Spawn Mung ",
    "pattern": "Always: 41% 6 Dmg Melee /  29% Consume 1 random Pigment Status card in Any for 3 Power, 6 Block / 30% 4 Pain, Spawn Mungie",
    "game": "Brutal Orchestra",
    "location": "Desert",
    "dice": [
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
            "raw": "Pain 2",
            "value": null,
            "move": "Pain",
            "addons": [
              "2"
            ],
            "target": null
          },
          {
            "raw": "Spawn Mungie",
            "value": null,
            "move": "Spawn",
            "addons": [],
            "target": "Mungie"
          }
        ],
        "raw": "Pain 2, Spawn Mungie"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "Pain 2",
            "value": null,
            "move": "Pain",
            "addons": [
              "2"
            ],
            "target": null
          },
          {
            "raw": "Spawn Mungie",
            "value": null,
            "move": "Spawn",
            "addons": [],
            "target": "Mungie"
          }
        ],
        "raw": "Pain 2, Spawn Mungie"
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
    ],
    "imageUrl": "images/enemies/MunglingMudLung.png",
    "variantOf": null
  },
  {
    "name": "Mungie",
    "type": "Intelligence",
    "difficulty": null,
    "weight": null,
    "hpMin": 12,
    "hpMax": 14,
    "ability": "Pigment Rich",
    "pattern": "Always: 3 Dmg Melee",
    "game": "Brutal Orchestra",
    "location": "Desert",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "1 Dmg",
            "value": 1,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "1 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "1 Dmg",
            "value": 1,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "1 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "1 Dmg",
            "value": 1,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "1 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "1 Dmg",
            "value": 1,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "1 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "1 Dmg",
            "value": 1,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "1 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "1 Dmg",
            "value": 1,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "1 Dmg"
      }
    ],
    "imageUrl": "images/enemies/Mungie.png",
    "variantOf": null
  },
  {
    "name": "Revola",
    "type": "Intelligence",
    "difficulty": "Medium",
    "weight": 3,
    "hpMin": 130,
    "hpMax": 140,
    "ability": "Pigment Rich / Forgetful / Barricade",
    "pattern": "Always: 41% 3 Dmg Ranged, 3 Oiled / 41% 15 Dmg Ranged, 16 Block / 18% Alter Revola (Standing), Gain 2 Frail",
    "game": "Brutal Orchestra",
    "location": "Watery",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "Alter Revola (Standing)",
            "value": null,
            "move": "Alter",
            "addons": [],
            "target": "Revola (Standing)"
          }
        ],
        "raw": "Alter Revola (Standing)"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "3 Oiled",
            "value": 3,
            "move": "Oiled",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg, 3 Oiled"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "3 Oiled",
            "value": 3,
            "move": "Oiled",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg, 3 Oiled"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "4Block Cleave",
            "value": 4,
            "move": "Cleave",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg, 4Block Cleave"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "4 Block Cleave",
            "value": 4,
            "move": "Block",
            "addons": [
              "Cleave"
            ],
            "target": null
          }
        ],
        "raw": "4 Dmg, 4 Block Cleave"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "4 Block Cleave",
            "value": 4,
            "move": "Block",
            "addons": [
              "Cleave"
            ],
            "target": null
          }
        ],
        "raw": "4 Dmg, 4 Block Cleave"
      }
    ],
    "imageUrl": "images/enemies/Revola.png",
    "variantOf": null
  },
  {
    "name": "Revola (Standing)",
    "type": "Intelligence",
    "difficulty": null,
    "weight": null,
    "hpMin": 130,
    "hpMax": 140,
    "ability": "Pigment Rich / Forgetful / Barricade",
    "pattern": "Always: 77% 9 Dmg Melee, Inflict 3 Ruptured, 20 Block, Alter Revola, Lose All Frail / 23% Unknown Intent (\"Stood up too fast, got a headrush\")",
    "game": "Brutal Orchestra",
    "location": "Watery",
    "dice": [
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "3 Ruptured",
            "value": 3,
            "move": "Ruptured",
            "addons": [],
            "target": null
          },
          {
            "raw": "8 Block",
            "value": 8,
            "move": "Block",
            "addons": [],
            "target": null
          },
          {
            "raw": "Alter Revola",
            "value": null,
            "move": "Alter",
            "addons": [],
            "target": "Revola"
          }
        ],
        "raw": "4 Dmg, 3 Ruptured, 8 Block, Alter Revola"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "3 Ruptured",
            "value": 3,
            "move": "Ruptured",
            "addons": [],
            "target": null
          },
          {
            "raw": "8 Block",
            "value": 8,
            "move": "Block",
            "addons": [],
            "target": null
          },
          {
            "raw": "Alter Revola",
            "value": null,
            "move": "Alter",
            "addons": [],
            "target": "Revola"
          }
        ],
        "raw": "4 Dmg, 3 Ruptured, 8 Block, Alter Revola"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "3 Ruptured",
            "value": 3,
            "move": "Ruptured",
            "addons": [],
            "target": null
          },
          {
            "raw": "8 Block",
            "value": 8,
            "move": "Block",
            "addons": [],
            "target": null
          },
          {
            "raw": "Alter Revola",
            "value": null,
            "move": "Alter",
            "addons": [],
            "target": "Revola"
          }
        ],
        "raw": "4 Dmg, 3 Ruptured, 8 Block, Alter Revola"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "3 Ruptured",
            "value": 3,
            "move": "Ruptured",
            "addons": [],
            "target": null
          },
          {
            "raw": "8 Block",
            "value": 8,
            "move": "Block",
            "addons": [],
            "target": null
          },
          {
            "raw": "Alter Revola",
            "value": null,
            "move": "Alter",
            "addons": [],
            "target": "Revola"
          }
        ],
        "raw": "4 Dmg, 3 Ruptured, 8 Block, Alter Revola"
      }
    ],
    "imageUrl": "images/enemies/RevolaStanding.png",
    "variantOf": "Revola"
  },
  {
    "name": "Skinning Homunculus",
    "type": "Intelligence",
    "difficulty": "High",
    "weight": 5,
    "hpMin": 100,
    "hpMax": 110,
    "ability": "Formless / When another ally takes Melee Dmg, Add 1 Frail Overload to Intent",
    "pattern": "Always: 43% 10 Dmg Ranged Overload / 43% 10 Dmg Ranged Overload / 14% 40 Dmg Ranged, 35 Pain",
    "game": "Brutal Orchestra",
    "location": "Chaos",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg Overload",
            "value": 3,
            "move": "Dmg",
            "addons": [
              "Overload"
            ],
            "target": null
          }
        ],
        "raw": "3 Dmg Overload"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg Overload",
            "value": 3,
            "move": "Dmg",
            "addons": [
              "Overload"
            ],
            "target": null
          }
        ],
        "raw": "3 Dmg Overload"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg Overload",
            "value": 3,
            "move": "Dmg",
            "addons": [
              "Overload"
            ],
            "target": null
          }
        ],
        "raw": "3 Dmg Overload"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg Overload",
            "value": 3,
            "move": "Dmg",
            "addons": [
              "Overload"
            ],
            "target": null
          }
        ],
        "raw": "3 Dmg Overload"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg Overload",
            "value": 3,
            "move": "Dmg",
            "addons": [
              "Overload"
            ],
            "target": null
          }
        ],
        "raw": "3 Dmg Overload"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "8 Dmg Overload",
            "value": 8,
            "move": "Dmg",
            "addons": [
              "Overload"
            ],
            "target": null
          }
        ],
        "raw": "8 Dmg Overload"
      }
    ],
    "imageUrl": "images/enemies/SkinningHomunculus.png",
    "variantOf": null
  },
  {
    "name": "Hobgoblin",
    "type": "Dexterity",
    "difficulty": "Low",
    "weight": 1,
    "hpMin": 30,
    "hpMax": 34,
    "ability": "Rerollable",
    "pattern": "Always: D8 Dmg Melee",
    "game": "Rogue",
    "location": "General",
    "dice": [
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
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
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      }
    ],
    "imageUrl": "images/enemies/Hobgoblin.png",
    "variantOf": null
  },
  {
    "name": "Aquator",
    "type": "Dexterity",
    "difficulty": "Medium",
    "weight": 2,
    "hpMin": 40,
    "hpMax": 46,
    "ability": "Rust, Rerollable",
    "pattern": "Always: D6x3 Dmg Melee",
    "game": "Rogue",
    "location": "General",
    "dice": [
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      }
    ],
    "imageUrl": "images/enemies/Aquator.png",
    "variantOf": null
  },
  {
    "name": "Troll",
    "type": "Dexterity",
    "difficulty": "Medium",
    "weight": 4,
    "hpMin": 60,
    "hpMax": 66,
    "ability": "Rerollable",
    "pattern": "Always: D8x2 + D6x2 Dmg Melee",
    "game": "Rogue",
    "location": "General",
    "dice": [
      {
        "isBlank": true,
        "effects": []
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
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "5 Dmg",
            "value": 5,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "5 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "6 Dmg",
            "value": 6,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "6 Dmg"
      }
    ],
    "imageUrl": "images/enemies/Troll.png",
    "variantOf": null
  },
  {
    "name": "Dragon",
    "type": "Dexterity",
    "difficulty": "High",
    "weight": 9,
    "hpMin": 250,
    "hpMax": 270,
    "ability": "Immune to Burn, Rerollable",
    "pattern": "Always: 50% D6x6 Dmg Ranged, 5 Burn / 50% D8x2 +D10x3 Dmg Melee",
    "game": "Rogue",
    "location": "General",
    "dice": [
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Dmg 1 Burn",
            "value": 2,
            "move": "Dmg",
            "addons": [
              "1",
              "Burn"
            ],
            "target": null
          }
        ],
        "raw": "2 Dmg 1 Burn"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg 2 Burn",
            "value": 4,
            "move": "Dmg",
            "addons": [
              "2",
              "Burn"
            ],
            "target": null
          }
        ],
        "raw": "4 Dmg 2 Burn"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "6 Dmg 3 Burn",
            "value": 6,
            "move": "Dmg",
            "addons": [
              "3",
              "Burn"
            ],
            "target": null
          }
        ],
        "raw": "6 Dmg 3 Burn"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "8 Dmg 4 Burn",
            "value": 8,
            "move": "Dmg",
            "addons": [
              "4",
              "Burn"
            ],
            "target": null
          }
        ],
        "raw": "8 Dmg 4 Burn"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "10 Dmg 5  Burn",
            "value": 10,
            "move": "Dmg",
            "addons": [
              "5",
              "Burn"
            ],
            "target": null
          }
        ],
        "raw": "10 Dmg 5  Burn"
      }
    ],
    "imageUrl": "images/enemies/Dragon.png",
    "variantOf": null
  },
  {
    "name": "Cultist",
    "type": "Charisma",
    "difficulty": "Low",
    "weight": 2,
    "hpMin": 48,
    "hpMax": 54,
    "ability": "N/A",
    "pattern": "Turn 1: Get 3 Ritual | Next: 6 Dmg Melee",
    "game": "Slay the Spire",
    "location": "General",
    "dice": [
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      },
      {
        "isBlank": true,
        "effects": []
      }
    ],
    "imageUrl": "images/enemies/Cultist.png",
    "variantOf": null
  },
  {
    "name": "Snecko",
    "type": "Charisma",
    "difficulty": "Medium",
    "weight": 6,
    "hpMin": 114,
    "hpMax": 120,
    "ability": "N/A",
    "pattern": "Turn 1: Inflict 6 Confused | Next: 60% 8 Dmg Melee 2 Vulnerable / 40% 15 Dmg Melee",
    "game": "Slay the Spire",
    "location": "General",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "Inflict 4 Confused Exhert",
            "value": 4,
            "move": "Inflict",
            "addons": [
              "Exhert"
            ],
            "target": "Confused"
          }
        ],
        "raw": "Inflict 4 Confused Exhert"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "Inflict 4 Confused Exhert",
            "value": 4,
            "move": "Inflict",
            "addons": [
              "Exhert"
            ],
            "target": "Confused"
          }
        ],
        "raw": "Inflict 4 Confused Exhert"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Dmg 2 Frail",
            "value": 2,
            "move": "Dmg",
            "addons": [
              "2",
              "Frail"
            ],
            "target": null
          }
        ],
        "raw": "2 Dmg 2 Frail"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Dmg 2 Frail",
            "value": 2,
            "move": "Dmg",
            "addons": [
              "2",
              "Frail"
            ],
            "target": null
          }
        ],
        "raw": "2 Dmg 2 Frail"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg"
      }
    ],
    "imageUrl": "images/enemies/Snecko.png",
    "variantOf": null
  },
  {
    "name": "Transient",
    "type": "Charisma",
    "difficulty": "High",
    "weight": 9,
    "hpMin": 999,
    "hpMax": 999,
    "ability": "Fading 4/Shifting",
    "pattern": "Always: 30 + (Turn Number - 1 x 10) Dmg Melee",
    "game": "Slay the Spire",
    "location": "General",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "5 x Turn number Dmg",
            "value": 5,
            "move": "x",
            "addons": [
              "Turn",
              "number",
              "Dmg"
            ],
            "target": null
          }
        ],
        "raw": "5 x Turn number Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "5 x Turn number Dmg",
            "value": 5,
            "move": "x",
            "addons": [
              "Turn",
              "number",
              "Dmg"
            ],
            "target": null
          }
        ],
        "raw": "5 x Turn number Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "5 x Turn number Dmg",
            "value": 5,
            "move": "x",
            "addons": [
              "Turn",
              "number",
              "Dmg"
            ],
            "target": null
          }
        ],
        "raw": "5 x Turn number Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "5 x Turn number Dmg",
            "value": 5,
            "move": "x",
            "addons": [
              "Turn",
              "number",
              "Dmg"
            ],
            "target": null
          }
        ],
        "raw": "5 x Turn number Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "5 x Turn number Dmg",
            "value": 5,
            "move": "x",
            "addons": [
              "Turn",
              "number",
              "Dmg"
            ],
            "target": null
          }
        ],
        "raw": "5 x Turn number Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "5 x Turn number Dmg",
            "value": 5,
            "move": "x",
            "addons": [
              "Turn",
              "number",
              "Dmg"
            ],
            "target": null
          }
        ],
        "raw": "5 x Turn number Dmg"
      }
    ],
    "imageUrl": "images/enemies/Transient.png",
    "variantOf": null
  },
  {
    "name": "Bones",
    "type": "Intelligence",
    "difficulty": "Low",
    "weight": 1,
    "hpMin": 30,
    "hpMax": 34,
    "ability": "When Defeated, 5 Dmg to it's adjacent allies",
    "pattern": "Always: 60% 9 Dmg Melee / 40% 6 Dmg Melee",
    "game": "Slice & Dice",
    "location": "Undead",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "3 Dmg",
            "value": 3,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "3 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg"
      }
    ],
    "imageUrl": "images/enemies/Bones.png",
    "variantOf": null
  },
  {
    "name": "Fanatic",
    "type": "Intelligence",
    "difficulty": "Medium",
    "weight": 3,
    "hpMin": 15,
    "hpMax": 15,
    "ability": "N/A",
    "pattern": "Always: 33% 20 Dmg Melee, 20 Pain / 33% 15 Dmg Melee, 15 Pain / 33% 10 Dmg Melee, 10 Pain",
    "game": "Slice & Dice",
    "location": "General",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "4 Pain",
            "value": 4,
            "move": "Pain",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg, 4 Pain "
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "4 Dmg",
            "value": 4,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "4 Pain",
            "value": 4,
            "move": "Pain",
            "addons": [],
            "target": null
          }
        ],
        "raw": "4 Dmg, 4 Pain "
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "6 Dmg",
            "value": 6,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "6 Pain",
            "value": 6,
            "move": "Pain",
            "addons": [],
            "target": null
          }
        ],
        "raw": "6 Dmg, 6 Pain "
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "6 Dmg",
            "value": 6,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "6 Pain",
            "value": 6,
            "move": "Pain",
            "addons": [],
            "target": null
          }
        ],
        "raw": "6 Dmg, 6 Pain "
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "8 Dmg",
            "value": 8,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "8 Pain",
            "value": 8,
            "move": "Pain",
            "addons": [],
            "target": null
          }
        ],
        "raw": "8 Dmg, 8 Pain "
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "8 Dmg",
            "value": 8,
            "move": "Dmg",
            "addons": [],
            "target": null
          },
          {
            "raw": "8 Pain",
            "value": 8,
            "move": "Pain",
            "addons": [],
            "target": null
          }
        ],
        "raw": "8 Dmg, 8 Pain "
      }
    ],
    "imageUrl": "images/enemies/Fanatic.png",
    "variantOf": null
  },
  {
    "name": "Spiker",
    "type": "Intelligence",
    "difficulty": "High",
    "weight": 3,
    "hpMin": 20,
    "hpMax": 20,
    "ability": "3 Thorns",
    "pattern": "Always 60% 15 Dmg Melee / 40% 10 Dmg Ranged, Gain 1 Thorns",
    "game": "Slice & Dice",
    "location": "General",
    "dice": [
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Dmg Wide",
            "value": 2,
            "move": "Dmg",
            "addons": [
              "Wide"
            ],
            "target": null
          }
        ],
        "raw": "2 Dmg Wide"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "2 Dmg Wide",
            "value": 2,
            "move": "Dmg",
            "addons": [
              "Wide"
            ],
            "target": null
          }
        ],
        "raw": "2 Dmg Wide"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "7 Dmg",
            "value": 7,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "7 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "7 Dmg",
            "value": 7,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "7 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "7 Dmg",
            "value": 7,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "7 Dmg"
      },
      {
        "isBlank": false,
        "effects": [
          {
            "raw": "7 Dmg",
            "value": 7,
            "move": "Dmg",
            "addons": [],
            "target": null
          }
        ],
        "raw": "7 Dmg"
      }
    ],
    "imageUrl": "images/enemies/Spiker.png",
    "variantOf": null
  }
];
