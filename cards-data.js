// Auto-generated from Roguelikes.xlsx - Cards
// Card deck system: players build a deck from this pool

var CARDS_DATA = [
  {
    "name": "Strike",
    "rarity": "Starter",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 6 Dmg Melee.",
    "upgradedDescription": "Deal 9 Dmg Melee.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": null,
    "game": null,
    "tags": []
  },
  {
    "name": "Defend",
    "rarity": "Starter",
    "cost": 1,
    "type": "Skill",
    "description": "Gain 5 Block.",
    "upgradedDescription": "Gain 8 Block.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": null,
    "game": null,
    "tags": []
  },
  {
    "name": "Bash",
    "rarity": "Starter",
    "cost": 2,
    "type": "Attack",
    "description": "Deal 8 Dmg Melee. Inflict 2 Vulnerable.",
    "upgradedDescription": "Deal 10 Dmg Melee. Apply 3 Vulnerable.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Bash.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Feed",
    "rarity": "Rare",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 10 Dmg Melee. Infuse 3. Exhaust.",
    "upgradedDescription": "Deal 12 Dmg Melee. Infuse 4. Exhaust.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Feed.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Shrug It Off",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Gain 8 Block. Draw 1 Card.",
    "upgradedDescription": "Gain 11 Block. Draw 1 card.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/ShrugItOff.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Pommel Strike",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 9 Dmg Melee. Draw 1 card.",
    "upgradedDescription": "Deal 10 Dmg Melee. Draw 2 cards.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/PommelStrike.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Disarm",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Enemy loses 2 Power. Exhaust.",
    "upgradedDescription": "Enemy loses 3 Power. Exhaust.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Disarm.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Isaac's D6",
    "rarity": "Starter",
    "cost": 1,
    "type": "Dice",
    "description": "1: Gain random curse from the current difficulty.\n2: Take 3 Dmg\n3: Gain 5 Block\n4: Heal 3 Health\n5: Draw 1 Card\n6: Gain a Random Common Item",
    "upgradedDescription": "1: Gain 2 random curses from the current difficulty.\n2: Take 5 Dmg\n3: Gain 8 Block\n4: Heal 3 Health\n5: Draw 2 Cards\n6: Gain a Random Item",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": null,
    "game": "The Binding of Isaac",
    "tags": []
  },
  {
    "name": "Demon Form",
    "rarity": "Rare",
    "cost": 3,
    "type": "Power",
    "description": "At the start of each turn, gain 2 Power.",
    "upgradedDescription": "At the start of each turn, gain 3 Power.",
    "upgradedCost": 3,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/DemonForm.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Bloodletting",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Skill",
    "description": "Lose 3 Health. Gain 2 Energy.",
    "upgradedDescription": "Lose 3 Health. Gain 3 Energy.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Bloodletting.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Barrel",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 5 Dmg Ranged. Fishing Weight.",
    "upgradedDescription": "Deal 5 Dmg Ranged. Fishing Weight.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/weapons/Barrel.png",
    "game": "Enter the Gungeon",
    "tags": [
      "weapon"
    ]
  },
  {
    "name": "Blasma Pistol",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 2 Dmg Ranged. Wealth.",
    "upgradedDescription": "Deal 2 Dmg Ranged. Wealth.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/weapons/BlasmaPistol.png",
    "game": "Flinthook",
    "tags": [
      "weapon"
    ]
  },
  {
    "name": "Lil' Bomber",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 3 Dmg Ranged.",
    "upgradedDescription": "Deal 3 Dmg Ranged.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/weapons/LilBomber.png",
    "game": "Enter the Gungeon",
    "tags": [
      "weapon"
    ]
  },
  {
    "name": "Blood Magic",
    "rarity": "Rare",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 2x3 Dmg Ranged. Indiscriminate. 2 Infuse.",
    "upgradedDescription": "Deal 2x3 Dmg Ranged. Indiscriminate. 2 Infuse.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/weapons/BloodMagic.png",
    "game": "Megabonk",
    "tags": [
      "weapon"
    ]
  },
  {
    "name": "Dexecutioner",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Attack",
    "description": "5 Assassinate.",
    "upgradedDescription": "5 Assassinate.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/weapons/Dexecutioner.png",
    "game": "Megabonk",
    "tags": [
      "weapon"
    ]
  },
  {
    "name": "Blue Pigment",
    "rarity": "None",
    "cost": 1,
    "type": "Status",
    "description": "Gain +3 Intelligence until end of combat. Exhaust.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": true,
    "imageUrl": "images/cards/BluePigment.png",
    "game": "Brutal Orchestra",
    "tags": [
      "pigment"
    ]
  },
  {
    "name": "Purple Pigment",
    "rarity": "None",
    "cost": 1,
    "type": "Status",
    "description": "Gain +3 Charisma until end of combat. Exhaust.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": true,
    "imageUrl": "images/cards/PurplePigment.png",
    "game": "Brutal Orchestra",
    "tags": [
      "pigment"
    ]
  },
  {
    "name": "Red Pigment",
    "rarity": "None",
    "cost": 1,
    "type": "Status",
    "description": "Gain +3 Strength until end of combat. Exhaust.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": true,
    "imageUrl": "images/cards/RedPigment.png",
    "game": "Brutal Orchestra",
    "tags": [
      "pigment"
    ]
  },
  {
    "name": "Yellow Pigment",
    "rarity": "None",
    "cost": 1,
    "type": "Status",
    "description": "Gain +3 Dexterity until end of combat. Exhaust.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": true,
    "imageUrl": "images/cards/YellowPigment.png",
    "game": "Brutal Orchestra",
    "tags": [
      "pigment"
    ]
  },
  {
    "name": "Barricade",
    "rarity": "Rare",
    "cost": 3,
    "type": "Power",
    "description": "Gain Barricade.",
    "upgradedDescription": "Gain Barricade.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Barricade.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Claw",
    "rarity": "Common",
    "cost": 0,
    "type": "Attack",
    "description": "Deal 3 Dmg Melee. Increase the damage of ALL Claw cards by 2 this combat.",
    "upgradedDescription": "Deal 4 Dmg Melee. Increase the damage of ALL Claw cards by 3 this combat.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Claw.png",
    "game": "Slay the Spire",
    "tags": [
      "Defect"
    ]
  },
  {
    "name": "Target Practice",
    "rarity": "Uncommon",
    "cost": 3,
    "type": "Training",
    "description": "Permanently Gain +1 Strength and +2 Charisma. Destroy.",
    "upgradedDescription": "Permanently Gain +2 Strength and +3 Charisma. Destroy.",
    "upgradedCost": 3,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/TargetPractice.png",
    "game": "Monmusu Gladiator",
    "tags": []
  },
  {
    "name": "Boulder Dodge",
    "rarity": "Uncommon",
    "cost": 3,
    "type": "Training",
    "description": "Permanently Gain +1 Intelligence and +2 Dexterity. Destroy.",
    "upgradedDescription": "Permanently Gain +2 Intelligence and +3 Dexterity. Destroy.",
    "upgradedCost": 3,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/BoulderDodge.png",
    "game": "Monmusu Gladiator",
    "tags": []
  },
  {
    "name": "Mock Battle",
    "rarity": "Rare",
    "cost": 5,
    "type": "Training",
    "description": "Permanently Gain +2 Strength, Dexterity, Intelligence, and Charisma. Destroy.",
    "upgradedDescription": "Permanently Gain +2 Strength, Dexterity, Intelligence, and Charisma. Destroy.",
    "upgradedCost": 4,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/MockBattle.png",
    "game": "Monmusu Gladiator",
    "tags": []
  },
  {
    "name": "Runner's High",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Training",
    "description": "For every 10 Health you have under Max Health, Gain +2 Max Health. Destroy.",
    "upgradedDescription": "For every 10 Health you have under Max Health, Gain +3 Max Health. Destroy. ",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Runner'sHigh.png",
    "game": "Monmusu Gladiator",
    "tags": []
  },
  {
    "name": "Slimed",
    "rarity": "None",
    "cost": 1,
    "type": "Status",
    "description": "Draw 1 card. Exhaust.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": true,
    "imageUrl": "images/cards/Slimed.png",
    "game": "Slay the Spire",
    "tags": []
  },
  {
    "name": "Cleave",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 8 Dmg Melee Cleave.",
    "upgradedDescription": "Deal 11 Dmg Melee Cleave.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Cleave.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Clothesline",
    "rarity": "Common",
    "cost": 2,
    "type": "Attack",
    "description": "Deal 12 Dmg Melee. Inflict 2 Weak.",
    "upgradedDescription": "Deal 14 Dmg Melee. Inflict 3 Weak.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Clothesline.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Carnage",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Attack",
    "description": "Ethereal. Deal 20 Dmg Melee",
    "upgradedDescription": "Ethereal. Deal 28 Dmg Melee.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Carnage.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Inflame",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "Gain 2 Power.",
    "upgradedDescription": "Gain 3 Power.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Inflame.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Twin Strike",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 5x2 Dmg Melee.",
    "upgradedDescription": "Deal 7x2 Dmg Melee.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/TwinStrike.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Uppercut",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Attack",
    "description": "Deal 13 Dmg Melee. Inflict 1 Weak. Inflict 1 Vulnerable.",
    "upgradedDescription": "Deal 13 Dmg Melee. Inflict 2 Weak. Inflict 2 Vulnerable.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Uppercut.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad"
    ]
  },
  {
    "name": "Adrenaline",
    "rarity": "Rare",
    "cost": 0,
    "type": "Skill",
    "description": "Gain 1 Energy. Draw 2 Cards. Exhaust.",
    "upgradedDescription": "Gain 2 Energy. Draw 2 Cards. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Adrenaline.png",
    "game": "Slay the Spire",
    "tags": [
      "silent"
    ]
  }
];
