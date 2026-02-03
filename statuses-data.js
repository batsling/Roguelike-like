// Auto-generated from Roguelikes.xlsx - Combat Statuses

var STATUSES_DATA = {
  "burn": {
    "name": "Burn",
    "description": "Deals 3 damage to any target per stack",
    "type": "Debuff",
    "stackable": true,
    "maxStack": null,
    "decay": "Down by 1 at end of turn",
    "who": "All",
    "preference": "Negative",
    "imageUrl": "images/statuses/Burn.png"
  },
  "poison": {
    "name": "Poison",
    "description": "Deals X damage to any target where X is the stack ",
    "type": "Debuff",
    "stackable": true,
    "maxStack": null,
    "decay": "Down by 1 at end of turn",
    "who": "All",
    "preference": "Negative",
    "imageUrl": "images/statuses/Poison.png"
  },
  "dodge": {
    "name": "Dodge",
    "description": "Negate the next X sources of damage where X is the stack",
    "type": "Buff",
    "stackable": true,
    "maxStack": null,
    "decay": "Stack Goes down when hit",
    "who": "All",
    "preference": "Positive",
    "imageUrl": "images/statuses/Dodge.png"
  },
  "power": {
    "name": "Power",
    "description": "Raise or Lower the damage dealth by this target by X",
    "type": "Buff",
    "stackable": true,
    "maxStack": null,
    "decay": "None",
    "who": "All",
    "preference": "Positive",
    "imageUrl": "images/statuses/Power.png"
  },
  "oiled": {
    "name": "Oiled",
    "description": "Burn deals double damage, and at end of turn, Dex save 10 or Lose 1 Energy",
    "type": "Debuff",
    "stackable": true,
    "maxStack": null,
    "decay": "Down by 1 at end of turn",
    "who": "All",
    "preference": "Negative",
    "imageUrl": "images/statuses/Oiled.png"
  },
  "forgetful": {
    "name": "Forgetful",
    "description": "Dice sides that have already been rolled cannot appear until all sides have been rolled",
    "type": "Ability",
    "stackable": false,
    "maxStack": 1,
    "decay": "Down by 1 when all sides have been rolled",
    "who": "All",
    "preference": "Negative",
    "imageUrl": "images/statuses/Forgetful.png"
  },
  "barricade": {
    "name": "Barricade",
    "description": "Block goes down by half at end of turn",
    "type": "Ability",
    "stackable": false,
    "maxStack": 1,
    "decay": "Down by 1 at end of turn",
    "who": "All",
    "preference": "Positive",
    "imageUrl": "images/statuses/Barricade.png"
  },
  "ruptured": {
    "name": "Ruptured",
    "description": "Deals 3 damage to the player when they dodge",
    "type": "Debuff",
    "stackable": true,
    "maxStack": null,
    "decay": "Down by 1 when dash is used",
    "who": "All",
    "preference": "Negative",
    "imageUrl": "images/statuses/Ruptured.png"
  },
  "frail": {
    "name": "Frail",
    "description": "All damage to target is doubled",
    "type": "Debuff",
    "stackable": true,
    "maxStack": null,
    "decay": "Down by 1 at end of turn",
    "who": "All",
    "preference": "Negative",
    "imageUrl": "images/statuses/Frail.png"
  },
  "formless": {
    "name": "Formless",
    "description": "When dealth damage, reroll's their intent die",
    "type": "Ability",
    "stackable": false,
    "maxStack": null,
    "decay": "None",
    "who": "Enemy",
    "preference": "Neutral",
    "imageUrl": "images/statuses/Formless.png"
  },
  "multi_attack_x": {
    "name": "Multi Attack X",
    "description": "This enemy rolls X amount of die at a time",
    "type": "Ability",
    "stackable": false,
    "maxStack": null,
    "decay": "None",
    "who": "Enemy",
    "preference": "Positive",
    "imageUrl": "images/statuses/MultiAttack.png"
  },
  "ritual": {
    "name": "Ritual",
    "description": "At the end of its turn, gains X Power",
    "type": "Buff",
    "stackable": true,
    "maxStack": null,
    "decay": "None",
    "who": "All",
    "preference": "Positive",
    "imageUrl": "images/statuses/Ritual.png"
  },
  "confused": {
    "name": "Confused",
    "description": "Each Dice Energy Cost is randomized between 0 and your max energy every roll",
    "type": "Debuff",
    "stackable": true,
    "maxStack": null,
    "decay": "Down by 1 at end of turn",
    "who": "Player",
    "preference": "Negative",
    "imageUrl": "images/statuses/Confused.png"
  },
  "fading_x": {
    "name": "Fading X",
    "description": "Dies in X turns",
    "type": "Debuff",
    "stackable": true,
    "maxStack": null,
    "decay": "Down by 1 at end of turn",
    "who": "All",
    "preference": "Negative",
    "imageUrl": "images/statuses/Fading.png"
  },
  "shifting": {
    "name": "Shifting",
    "description": "Loses X Power where X is the amount of damage taken this turn",
    "type": "Debuff",
    "stackable": false,
    "maxStack": null,
    "decay": "None",
    "who": "All",
    "preference": "Negative",
    "imageUrl": "images/statuses/Shifting.png"
  },
  "thorns": {
    "name": "Thorns",
    "description": "When a target with Thorns gets dealt Dmg directly, the attacker takes X Dmg",
    "type": "Buff",
    "stackable": true,
    "maxStack": null,
    "decay": "None",
    "who": "All",
    "preference": "Positive",
    "imageUrl": "images/statuses/Thorns.png"
  }
};
