// Auto-generated from Roguelikes.xlsx - Combat Moves

var MOVES_DATA = {
  "dmg": {
    "name": "Dmg",
    "description": "Deals X damage to target",
    "preferredTarget": "Enemy",
    "bonusStat": "Strength",
    "imageUrl": "images/moves/Attack.png"
  },
  "block": {
    "name": "Block",
    "description": "Give target X block, X amount of damage a target can take before it affects their health",
    "preferredTarget": "Ally/Self",
    "bonusStat": "Dexterity",
    "imageUrl": "images/moves/Defense.png"
  },
  "reroll": {
    "name": "Reroll",
    "description": "Gains X rerolls",
    "preferredTarget": "Self",
    "bonusStat": "Charisma",
    "imageUrl": "images/moves/Status.png"
  },
  "heal": {
    "name": "Heal",
    "description": "Give target X health",
    "preferredTarget": "Ally/Self",
    "bonusStat": "Intelligence",
    "imageUrl": "images/moves/Health.png"
  },
  "spawn": {
    "name": "Spawn",
    "description": "Spawn X Creature where X is the name of a creature. If used by enemies, the new enemy will have the Unknown intent showing \"Doing nothing\"",
    "preferredTarget": "Self",
    "bonusStat": "No",
    "imageUrl": "images/moves/Status.png"
  },
  "alter": {
    "name": "Alter",
    "description": "Alter target into X with the same Health as the original target, but Max Health of X",
    "preferredTarget": "Self",
    "bonusStat": "No",
    "imageUrl": "images/moves/Status.png"
  },
  "get": {
    "name": "Get",
    "description": "Give X status to self",
    "preferredTarget": "Self",
    "bonusStat": "Charisma",
    "imageUrl": "images/moves/Status.png"
  },
  "inflict": {
    "name": "Inflict",
    "description": "Inflict X status to target",
    "preferredTarget": "Enemy",
    "bonusStat": "Charisma",
    "imageUrl": "images/moves/Status.png"
  },
  "cleanse": {
    "name": "Cleanse",
    "description": "Removes X stacks of all debuff statuses",
    "preferredTarget": "Ally/Self",
    "bonusStat": "Charisma",
    "imageUrl": "images/moves/Status.png"
  },
  "mana": {
    "name": "Mana",
    "description": "Gain X Mana",
    "preferredTarget": "Self",
    "bonusStat": "Intelligence",
    "imageUrl": "images/moves/Mana.png"
  },
  "pain": {
    "name": "Pain",
    "description": "Whenever this side is rolled, target Deals X damage to self (not Melee or Ranged)",
    "preferredTarget": "Self",
    "bonusStat": "Strength",
    "imageUrl": "images/moves/Status.png"
  },
  "assassinate": {
    "name": "Assassinate",
    "description": "Kill an enemy with at least X health left",
    "preferredTarget": "Enemy",
    "bonusStat": "Strength",
    "imageUrl": "images/moves/Assassinate.png"
  },
  "vitality": {
    "name": "Vitality",
    "description": "Gain X Max Health",
    "preferredTarget": "Ally/Self",
    "bonusStat": "Intelligence",
    "imageUrl": "images/moves/Vitality.png"
  },
  "add x to (deck, hand, discard)": {
    "name": "Add X to (Deck, Hand, Discard)",
    "description": "Enemy gives X card to your Deck, Hand, or Discard",
    "preferredTarget": "Player",
    "bonusStat": "No",
    "imageUrl": "images/moves/Status.png"
  },
  "steal x in y": {
    "name": "Steal X in Y",
    "description": "Enemy Steals X Card from the player's Y(Deck, Hand, Discard, Any) for the duration of the battle",
    "preferredTarget": "Player",
    "bonusStat": "No",
    "imageUrl": "images/moves/Status.png"
  },
  "consume x in y for z": {
    "name": "Consume X in Y for Z",
    "description": "Steal X from the player's Y(Deck, Hand, Discard, Any) and then destroy it permanently and then Get z status if succesfully stolen and destroyed",
    "preferredTarget": "Player",
    "bonusStat": "No",
    "imageUrl": "images/moves/Status.png"
  },
  "lose ": {
    "name": "Lose ",
    "description": "Lose X status Y times (# or All)",
    "preferredTarget": "Self",
    "bonusStat": "No",
    "imageUrl": "images/moves/Status.png"
  }
};
