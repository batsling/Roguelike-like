// Dice face definitions for all card-type dice.
// Each face: { face, text, effects[], addons[], isBlank }
// effects[]: { move, value, addons[], statusKey, target }
// Face addons: 'cantrip', 'singleUse', 'druid'

var DICE_DATA = [
  {
    "name": "Isaac's D6",
    "sides": 6,
    "faces": [
      { "face": 1, "text": "Random Curse",   "effects": [], "addons": [], "isBlank": false, "isaacsTransform": "curse" },
      { "face": 2, "text": "Random Status",  "effects": [], "addons": [], "isBlank": false, "isaacsTransform": "status" },
      { "face": 3, "text": "Random Skill",   "effects": [], "addons": [], "isBlank": false, "isaacsTransform": "skill" },
      { "face": 4, "text": "Random Attack",  "effects": [], "addons": [], "isBlank": false, "isaacsTransform": "attack" },
      { "face": 5, "text": "Random Power",   "effects": [], "addons": [], "isBlank": false, "isaacsTransform": "power" },
      { "face": 6, "text": "Random Attack, Skill, or Power (free)", "effects": [], "addons": [], "isBlank": false, "isaacsTransform": "free_asp" }
    ]
  },
  {
    "name": "Mage Die",
    "sides": 6,
    "faces": [
      { "face": 1, "text": "Gain +2 Mana",   "effects": [{ "move": "mana", "value": 2, "addons": [], "target": "self" }], "addons": [], "isBlank": false },
      { "face": 2, "text": "Gain +2 Mana",   "effects": [{ "move": "mana", "value": 2, "addons": [], "target": "self" }], "addons": [], "isBlank": false },
      { "face": 3, "text": "Gain +1 Mana",   "effects": [{ "move": "mana", "value": 1, "addons": [], "target": "self" }], "addons": [], "isBlank": false },
      { "face": 4, "text": "Gain +1 Mana",   "effects": [{ "move": "mana", "value": 1, "addons": [], "target": "self" }], "addons": [], "isBlank": false },
      { "face": 5, "text": "—",          "effects": [], "addons": [], "isBlank": true },
      { "face": 6, "text": "—",          "effects": [], "addons": [], "isBlank": true }
    ]
  },
  {
    "name": "Mystic Die",
    "sides": 6,
    "faces": [
      { "face": 1, "text": "Gain +3 Block, +1 Health, +1 Mana",
        "effects": [
          { "move": "block", "value": 3, "addons": [], "target": "self" },
          { "move": "heal",  "value": 1, "addons": [], "target": "self" },
          { "move": "mana",  "value": 1, "addons": [], "target": "self" }
        ], "addons": [], "isBlank": false },
      { "face": 2, "text": "Gain +1 Health, +1 Mana",
        "effects": [
          { "move": "heal", "value": 1, "addons": [], "target": "self" },
          { "move": "mana", "value": 1, "addons": [], "target": "self" }
        ], "addons": [], "isBlank": false },
      { "face": 3, "text": "Gain +1 Health, +1 Mana",
        "effects": [
          { "move": "heal", "value": 1, "addons": [], "target": "self" },
          { "move": "mana", "value": 1, "addons": [], "target": "self" }
        ], "addons": [], "isBlank": false },
      { "face": 4, "text": "Gain +1 Health, +1 Mana",
        "effects": [
          { "move": "heal", "value": 1, "addons": [], "target": "self" },
          { "move": "mana", "value": 1, "addons": [], "target": "self" }
        ], "addons": [], "isBlank": false },
      { "face": 5, "text": "Gain +1 Mana",
        "effects": [{ "move": "mana", "value": 1, "addons": [], "target": "self" }], "addons": [], "isBlank": false },
      { "face": 6, "text": "—", "effects": [], "addons": [], "isBlank": true }
    ]
  },
  {
    "name": "Clumsy Die",
    "sides": 6,
    "faces": [
      { "face": 1, "text": "Deal 3 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 3, "addons": ["Melee"], "target": "enemy" }],
        "addons": ["cantrip"], "isBlank": false },
      { "face": 2, "text": "Take 3 Dmg",
        "effects": [{ "move": "pain", "value": 3, "addons": [], "target": "self" }],
        "addons": ["cantrip"], "isBlank": false },
      { "face": 3, "text": "Deal 3 Dmg Melee Cleave",
        "effects": [{ "move": "dmg", "value": 3, "addons": ["Melee", "Cleave"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 4, "text": "Deal 3 Dmg Melee Cleave",
        "effects": [{ "move": "dmg", "value": 3, "addons": ["Melee", "Cleave"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 5, "text": "Deal 3 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 3, "addons": ["Melee"], "target": "enemy" }],
        "addons": ["cantrip"], "isBlank": false },
      { "face": 6, "text": "Take 3 Dmg",
        "effects": [{ "move": "pain", "value": 3, "addons": [], "target": "self" }],
        "addons": ["cantrip"], "isBlank": false }
    ]
  },
  {
    "name": "Gambler Die",
    "sides": 6,
    "faces": [
      { "face": 1, "text": "Deal 15 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 15, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 2, "text": "Deal 12 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 12, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 3, "text": "—", "effects": [], "addons": [], "isBlank": true },
      { "face": 4, "text": "—", "effects": [], "addons": [], "isBlank": true },
      { "face": 5, "text": "Deal 1 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 1, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 6, "text": "—", "effects": [], "addons": [], "isBlank": true }
    ]
  },
  {
    "name": "Dabblest Die",
    "sides": 6,
    "faces": [
      { "face": 1, "text": "Gain +3 Mana",
        "effects": [{ "move": "mana", "value": 3, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 2, "text": "Deal 12 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 12, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 3, "text": "Deal 9 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 9, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 4, "text": "Deal 9 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 9, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 5, "text": "Gain +15 Block",
        "effects": [{ "move": "block", "value": 15, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 6, "text": "Gain +5 Health",
        "effects": [{ "move": "heal", "value": 5, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false }
    ]
  },
  {
    "name": "Druid Die",
    "sides": 6,
    "faces": [
      { "face": 1, "text": "Deal 6 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 6, "addons": ["Melee"], "target": "enemy" }],
        "addons": ["druid"], "isBlank": false },
      { "face": 2, "text": "Gain +6 Block",
        "effects": [{ "move": "block", "value": 6, "addons": [], "target": "self" }],
        "addons": ["druid"], "isBlank": false },
      { "face": 3, "text": "Gain +2 Mana",
        "effects": [{ "move": "mana", "value": 2, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 4, "text": "Gain +2 Mana",
        "effects": [{ "move": "mana", "value": 2, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 5, "text": "Gain +2 Health, Cleanse 2",
        "effects": [
          { "move": "heal",    "value": 2, "addons": [], "target": "self" },
          { "move": "cleanse", "value": 2, "addons": [], "target": "self" }
        ], "addons": [], "isBlank": false },
      { "face": 6, "text": "—", "effects": [], "addons": [], "isBlank": true }
    ]
  },
  {
    "name": "Jester Die",
    "sides": 6,
    "faces": [
      { "face": 1, "text": "Gain +3 Mana",
        "effects": [{ "move": "mana", "value": 3, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 2, "text": "Gain +1 Reroll",
        "effects": [{ "move": "reroll", "value": 1, "addons": [], "target": "self" }],
        "addons": ["cantrip"], "isBlank": false },
      { "face": 3, "text": "Gain +1 Mana",
        "effects": [{ "move": "mana", "value": 1, "addons": [], "target": "self" }],
        "addons": ["singleUse"], "isBlank": false },
      { "face": 4, "text": "Gain +1 Mana",
        "effects": [{ "move": "mana", "value": 1, "addons": [], "target": "self" }],
        "addons": ["singleUse"], "isBlank": false },
      { "face": 5, "text": "Gain +1 Buffer",
        "effects": [{ "move": "get", "value": 1, "addons": [], "target": "self", "statusKey": "buffer" }],
        "addons": [], "isBlank": false },
      { "face": 6, "text": "—", "effects": [], "addons": [], "isBlank": true }
    ]
  },
  {
    "name": "Defender Die",
    "sides": 6,
    "faces": [
      { "face": 1, "text": "Gain +9 Block",
        "effects": [{ "move": "block", "value": 9, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 2, "text": "Gain +6 Block",
        "effects": [{ "move": "block", "value": 6, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 3, "text": "Deal 3 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 3, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 4, "text": "Deal 3 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 3, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 5, "text": "Gain +3 Block",
        "effects": [{ "move": "block", "value": 3, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 6, "text": "—", "effects": [], "addons": [], "isBlank": true }
    ]
  },
  {
    "name": "Warden Die",
    "sides": 6,
    "faces": [
      { "face": 1, "text": "Gain +12 Block",
        "effects": [{ "move": "block", "value": 12, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 2, "text": "Gain +9 Block",
        "effects": [{ "move": "block", "value": 9, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 3, "text": "Deal 6 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 6, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 4, "text": "Deal 6 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 6, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 5, "text": "Gain +6 Block",
        "effects": [{ "move": "block", "value": 6, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 6, "text": "Gain +3 Block",
        "effects": [{ "move": "block", "value": 3, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false }
    ]
  },
  {
    "name": "Fighter Die",
    "sides": 6,
    "faces": [
      { "face": 1, "text": "Deal 6 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 6, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 2, "text": "Deal 6 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 6, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 3, "text": "Deal 3 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 3, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 4, "text": "Deal 3 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 3, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 5, "text": "Gain +3 Block",
        "effects": [{ "move": "block", "value": 3, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 6, "text": "Gain +3 Block",
        "effects": [{ "move": "block", "value": 3, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false }
    ]
  },
  {
    "name": "Soldier Die",
    "sides": 6,
    "faces": [
      { "face": 1, "text": "Deal 9 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 9, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 2, "text": "Deal 9 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 9, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 3, "text": "Deal 6 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 6, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 4, "text": "Deal 6 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 6, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 5, "text": "Gain +6 Block",
        "effects": [{ "move": "block", "value": 6, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 6, "text": "Gain +6 Block",
        "effects": [{ "move": "block", "value": 6, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false }
    ]
  },
  {
    "name": "Veteran Die",
    "sides": 6,
    "faces": [
      { "face": 1, "text": "Deal 12 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 12, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 2, "text": "Deal 12 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 12, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 3, "text": "Deal 9 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 9, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 4, "text": "Deal 9 Dmg Melee",
        "effects": [{ "move": "dmg", "value": 9, "addons": ["Melee"], "target": "enemy" }],
        "addons": [], "isBlank": false },
      { "face": 5, "text": "Gain +9 Block",
        "effects": [{ "move": "block", "value": 9, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false },
      { "face": 6, "text": "Gain +9 Block",
        "effects": [{ "move": "block", "value": 9, "addons": [], "target": "self" }],
        "addons": [], "isBlank": false }
    ]
  }
];
