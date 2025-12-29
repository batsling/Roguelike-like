var EVENTS_DATA = [
  {
    "name": "Primordial Teleporter",
    "description": "A trio of Stone Golems back you up into what seems to be an ancient teleporter. Do you activate it?",
    "options": [
      "Enter the teleporter (Teleport to random Action game)",
      "Interact with the teleporter, then enter it (Go back 3 difficulty, teleport to starting game)",
      "Fight off the Stone Golems (Fight 3 Stone Golems in a row)"
    ],
    "requirement": null
  },
  {
    "name": "A Wild Muncher Appears",
    "description": "You come across a green chest that looks hungry. Should you feed it?",
    "options": [
      "Feed it four items (Trade 4 items for 2 items based on luck)",
      "Feed it two items (Trade 2 items for 1 item based on luck)",
      "Leave it hungry"
    ],
    "requirement": {
      "type": "minItems",
      "value": 4
    }
  },
  {
    "name": "The Colosseum",
    "description": "You wake up in the center of a roaring arena, and must survive as long as you can. You must fight off an enemy and then are given the choice to escape or double down.",
    "options": [
      "Continue (Teleport to arena game)"
    ],
    "requirement": null
  }
];