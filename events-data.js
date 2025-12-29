var EVENTS_DATA = [
  {
    "name": "Primordial Teleporter",
    "description": "A trio of Stone Golems back you up into what seems to be an ancient teleporter. Do you activate it?",
    "options": [
      "Enter the teleporter",
      "Interact with the teleporter, then enter it",
      "Fight off the Stone Golems"
    ],
    "requirement": null
  },
  {
    "name": "A Wild Muncher Appears",
    "description": "You come across a green chest that looks hungry. Should you feed it?",
    "options": [
      "Feed it four items",
      "Feed it two items",
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
      "Continue"
    ],
    "requirement": null
  }
];