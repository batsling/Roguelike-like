// Auto-generated from Roguelikes.xlsx - Combat Moves

const MOVES_DATA = {
  "add x y to z": {
    "name": "Add X Y to Z",
    "description": "Target gives X number of Y card to your Z (Deck, Hand, or Discard)",
    "preferredTarget": "Player",
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
  "assassinate": {
    "name": "Assassinate",
    "description": "Kill an enemy with at least X health left",
    "preferredTarget": "Enemy",
    "bonusStat": "No",
    "imageUrl": "images/moves/Assassinate.png"
  },
  "block": {
    "name": "Block",
    "description": "Give target X block, X amount of damage a target can take before it affects their health",
    "preferredTarget": "Ally/Self",
    "bonusStat": "No",
    "imageUrl": "images/moves/Defense.png"
  },
  "cleanse": {
    "name": "Cleanse",
    "description": "Removes X stacks of all debuff statuses",
    "preferredTarget": "Ally/Self",
    "bonusStat": "No",
    "imageUrl": "images/moves/Status.png"
  },
  "conjure x y to z": {
    "name": "Conjure X Y to Z",
    "description": "Create X number of Y named Cards to your Z (Hand, Discard, Exhaust, Discard)",
    "preferredTarget": "Self",
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
  "dmg": {
    "name": "Dmg",
    "description": "Deals X damage to target",
    "preferredTarget": "Enemy",
    "bonusStat": "No",
    "imageUrl": "images/moves/Attack.png"
  },
  "get": {
    "name": "Get",
    "description": "Give X status to self",
    "preferredTarget": "Self",
    "bonusStat": "No",
    "imageUrl": "images/moves/Status.png"
  },
  "heal": {
    "name": "Heal",
    "description": "Give target X health",
    "preferredTarget": "Ally/Self",
    "bonusStat": "No",
    "imageUrl": "images/moves/Health.png"
  },
  "inflict": {
    "name": "Inflict",
    "description": "Inflict X status to target",
    "preferredTarget": "Enemy",
    "bonusStat": "No",
    "imageUrl": "images/moves/Status.png"
  },
  "learn": {
    "name": "Learn",
    "description": "Add X Spell to your Spellbook",
    "preferredTarget": "Self",
    "bonusStat": "No",
    "imageUrl": "images/moves/Status.png"
  },
  "lose": {
    "name": "Lose",
    "description": "Target loses X status Y times (# or All)",
    "preferredTarget": "Self",
    "bonusStat": "No",
    "imageUrl": "images/moves/Status.png"
  },
  "magic dmg": {
    "name": "Magic Dmg",
    "description": "Deals X Magic damage to target. Magic Damage can Have Different Elements (Fire).",
    "preferredTarget": "Enemy",
    "bonusStat": "No",
    "imageUrl": "images/moves/Attack.png"
  },
  "mana": {
    "name": "Mana",
    "description": "Gain X Mana",
    "preferredTarget": "Self",
    "bonusStat": "No",
    "imageUrl": "images/moves/Mana.png"
  },
  "pain": {
    "name": "Pain",
    "description": "Target Loses X Health (not Melee or Ranged)",
    "preferredTarget": "Self",
    "bonusStat": "No",
    "imageUrl": "images/moves/Status.png"
  },
  "reroll": {
    "name": "Reroll",
    "description": "Gains X rerolls",
    "preferredTarget": "Self",
    "bonusStat": "No",
    "imageUrl": "images/moves/Status.png"
  },
  "spawn x y": {
    "name": "Spawn X Y",
    "description": "Spawn X number of Y where X is the number of creatures and Y is the name of a creature. If used by enemies, the new enemy will have the Unknown intent showing \"Spawning\"",
    "preferredTarget": "Self",
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
  "vitality": {
    "name": "Vitality",
    "description": "Gain X Max Health",
    "preferredTarget": "Ally/Self",
    "bonusStat": "No",
    "imageUrl": "images/moves/Vitality.png"
  }
};

if (typeof window !== 'undefined') window.MOVES_DATA = MOVES_DATA;
