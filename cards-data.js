// Auto-generated from Roguelikes.xlsx - Cards
// Card deck system

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
      "ironclad",
      "offense"
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
      "ironclad",
      "offense",
      "health"
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
      "ironclad",
      "block",
      "defense"
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
      "ironclad",
      "offense",
      "draw"
    ]
  },
  {
    "name": "Disarm",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Inflict -2 Power to Target. Exhaust.",
    "upgradedDescription": "Inflict -3 Power to Target. Exhaust.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Disarm.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "debuff"
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
      "ironclad",
      "scaling"
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
      "ironclad",
      "energy"
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
    "upgradedCost": 0,
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
    "upgradedCost": 0,
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
    "upgradedCost": 0,
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
    "upgradedCost": 0,
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
      "ironclad",
      "defense"
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
      "defect",
      "offense"
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
    "upgradedDescription": "For every 10 Health you have under Max Health, Gain +3 Max Health. Destroy.",
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
    "description": "Draw 1 Card. Exhaust.",
    "upgradedDescription": null,
    "upgradedCost": 0,
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
      "ironclad",
      "offense",
      "aoe"
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
      "ironclad",
      "offense",
      "debuff"
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
      "ironclad",
      "offense"
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
      "ironclad",
      "scaling"
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
      "ironclad",
      "offense"
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
      "ironclad",
      "offense",
      "debuff"
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
      "silent",
      "energy",
      "draw"
    ]
  },
  {
    "name": "Shiv",
    "rarity": "None",
    "cost": 0,
    "type": "Attack",
    "description": "Deal 4 Dmg Ranged. Exhaust.",
    "upgradedDescription": "Deal 6 Dmg Ranged. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": true,
    "imageUrl": "images/cards/Shiv.png",
    "game": "Slay the Spire",
    "tags": []
  },
  {
    "name": "Cloak and Dagger",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Gain 6 Block. Conjure 1 Shiv.",
    "upgradedDescription": "Gain 6 Block. Conjure 2 Shivs.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/CloakAndDagger.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "defense"
    ]
  },
  {
    "name": "Deadly Poison",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Inflict 5 Poison.",
    "upgradedDescription": "Inflict 7 Poison.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/DeadlyPoison.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "debuff"
    ]
  },
  {
    "name": "Noxious Fumes",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "At the start of each turn, Inflict 2 Poison Cleave",
    "upgradedDescription": "At the start of each turn, Inflict 3 Poison Cleave",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/NoxiousFumes.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "debuff",
      "aoe"
    ]
  },
  {
    "name": "After Image",
    "rarity": "Rare",
    "cost": 1,
    "type": "Power",
    "description": "Whenever you play a Card, Gain 1 Block",
    "upgradedDescription": "Innate. Whenever you play a Card, Gain 1 Block",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/AfterImage.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "defense"
    ]
  },
  {
    "name": "Prepared",
    "rarity": "Common",
    "cost": 0,
    "type": "Skill",
    "description": "Draw 1 Card. Discard 1 Card.",
    "upgradedDescription": "Draw 2 Cards. Discard 2 Cards.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Prepared.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "draw",
      "discard"
    ]
  },
  {
    "name": "Tactician",
    "rarity": "Uncommon",
    "cost": "No",
    "type": "Skill",
    "description": "Sly. Gain +1 Energy.",
    "upgradedDescription": "Sly. Gain +2 Energy.",
    "upgradedCost": "No",
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Tactician.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "energy",
      "discard"
    ]
  },
  {
    "name": "Poisoned Stab",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 6 Dmg Melee. Inflict 3 Poison.",
    "upgradedDescription": "Deal 8 Dmg Melee. Inflict 4 Poison.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/PoisonedStab.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense",
      "debuff"
    ]
  },
  {
    "name": "Dagger Spray",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 4x2 Dmg Ranged.",
    "upgradedDescription": "Deal 6x2 Dmg Ranged.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/DaggerSpray.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense",
      "aoe"
    ]
  },
  {
    "name": "Doppelganger",
    "rarity": "Rare",
    "cost": "X",
    "type": "Skill",
    "description": "Next turn, Draw X Cards and Gain X Energy. Exhaust.",
    "upgradedDescription": "Next turn, Draw X+1 Cards and Gain X+1 Energy. Exhaust.",
    "upgradedCost": "X",
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Doppelganger.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "draw",
      "energy"
    ]
  },
  {
    "name": "Leg Sweep",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Skill",
    "description": "Inflict 2 Weak. Gain 11 Block.",
    "upgradedDescription": "Inflict 3 Weak. Gain 14 Block.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/LegSweep.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "debuff",
      "defense"
    ]
  },
  {
    "name": "Heel Hook",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 5 Dmg Melee. If the target has Weak, Gain +1 Energy and Draw 1 Card",
    "upgradedDescription": "Deal 8 Dmg Melee. If the target has Weak, Gain +1 Energy and Draw 1 Card",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/HeelHook.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "debuff",
      "offense"
    ]
  },
  {
    "name": "Dash",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Attack",
    "description": "Gain +10 Block. Deal 10 Dmg Melee.",
    "upgradedDescription": "Gain +13 Block. Deal 13 Dmg Melee.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Dash.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense",
      "defense"
    ]
  },
  {
    "name": "Crippling Cloud",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Skill",
    "description": "Inflict 4 Poison Cleave and 2 Weak Cleave.",
    "upgradedDescription": "Inflict 7 Poison Cleave and 2 Weak Cleave.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/CripplingCloud.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "debuff",
      "aoe"
    ]
  },
  {
    "name": "Accuracy",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "Shivs deal +4 Dmg.",
    "upgradedDescription": "Shivs deal +6 Dmg.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Accuracy.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "scaling"
    ]
  },
  {
    "name": "Backflip",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Gain +5 Block. Draw 2 Cards.",
    "upgradedDescription": "Gain 8 Block. Draw 2 Cards.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Backflip.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "defense",
      "draw"
    ]
  },
  {
    "name": "Acrobatics",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Draw 3 Cards. Discard 1 Card.",
    "upgradedDescription": "Draw 4 Cards. Discard 1 Card.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Acrobatics.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "draw",
      "discard"
    ]
  },
  {
    "name": "Outmaneuver",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Next turn, Gain +2 Energy.",
    "upgradedDescription": "Next turn, Gain +3 energy",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Outmaneuver.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "energy"
    ]
  },
  {
    "name": "Skewer",
    "rarity": "Uncommon",
    "cost": "X",
    "type": "Attack",
    "description": "Deal 7xX Dmg Melee.",
    "upgradedDescription": "Deal 10xX Dmg Melee.",
    "upgradedCost": "X",
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Skewer.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense"
    ]
  },
  {
    "name": "Die Die Die",
    "rarity": "Rare",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 13 Dmg Ranged Cleave. Exhaust.",
    "upgradedDescription": "Deal 17 Dmg Ranged Cleave. Exhaust.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/DieDieDie.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense",
      "aoe"
    ]
  },
  {
    "name": "Neutralize",
    "rarity": "Starter",
    "cost": 0,
    "type": "Attack",
    "description": "Deal 3 Dmg Melee. Inflict 1 Weak.",
    "upgradedDescription": "Deal 4 Dmg Melee. Inflict 2 Weak.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Neutralize.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense",
      "debuff"
    ]
  },
  {
    "name": "Survivor",
    "rarity": "Starter",
    "cost": 1,
    "type": "Skill",
    "description": "Gain +8 Block. Discard 1 Card.",
    "upgradedDescription": "Gain +11 Block. Discard 1 Card.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Survivor.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "defense",
      "discard"
    ]
  },
  {
    "name": "Bane",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 7 Dmg Melee. If the target has Poison, deal 7x2 Dmg Melee instead.",
    "upgradedDescription": "Deal 10 Dmg Melee. If the target has Poison, deal 10x2 Dmg Melee instead.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Bane.png",
    "game": "Slay the Spire",
    "tags": ["silent", "offense", "debuff"]
  },
  {
    "name": "Blade Dance",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Conjure 3 Shivs to Hand.",
    "upgradedDescription": "Conjure 4 Shivs to Hand.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/BladeDance.png",
    "game": "Slay the Spire",
    "tags": ["silent", "offense"]
  },
  {
    "name": "Caltrops",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "Gain +3 Thorns.",
    "upgradedDescription": "Gain +5 Thorns.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Caltrops.png",
    "game": "Slay the Spire",
    "tags": ["silent", "defense"]
  },
  {
    "name": "Dagger Throw",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 9 Dmg Ranged. Draw 1 Card. Discard 1 Card.",
    "upgradedDescription": "Deal 12 Dmg Ranged. Draw 1 Card. Discard 1 Card.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/DaggerThrow.png",
    "game": "Slay the Spire",
    "tags": ["silent", "offense", "discard", "draw"]
  },
  {
    "name": "Deflect",
    "rarity": "Common",
    "cost": 0,
    "type": "Skill",
    "description": "Gain +4 Block.",
    "upgradedDescription": "Gain +7 Block.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Deflect.png",
    "game": "Slay the Spire",
    "tags": ["silent", "defense"]
  },
  {
    "name": "Dodge and Roll",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Gain +4 Block. Gain Next Turn Block equal to Block Gained.",
    "upgradedDescription": "Gain +6 Block. Gain Next Turn Block equal to Block Gained.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/DodgeAndRoll.png",
    "game": "Slay the Spire",
    "tags": ["silent", "defense"]
  },
  {
    "name": "Flying Knee",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 8 Dmg Melee. Next turn, Gain +1 Energy.",
    "upgradedDescription": "Deal 11 Dmg Melee. Next turn, Gain +1 Energy.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/FlyingKnee.png",
    "game": "Slay the Spire",
    "tags": ["silent", "offense", "energy"]
  },
  {
    "name": "Malaise",
    "rarity": "Rare",
    "cost": "X",
    "type": "Skill",
    "description": "Inflict -X Power and Inflict X Weak. Exhaust.",
    "upgradedDescription": "Inflict -(X+1) Power and Inflict X+1 Weak. Exhaust.",
    "upgradedCost": "X",
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Malaise.png",
    "game": "Slay the Spire",
    "tags": ["silent", "debuff"]
  },
  {
    "name": "Piercing Wail",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Inflict -6 Power Cleave and Inflict 6 Shackled Cleave.",
    "upgradedDescription": "Inflict -8 Power Cleave and Inflict 8 Shackled Cleave.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/PiercingWail.png",
    "game": "Slay the Spire",
    "tags": ["silent", "debuff"]
  },
  {
    "name": "Quick Slash",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 8 Dmg Melee. Draw 1 Card.",
    "upgradedDescription": "Deal 12 Dmg Melee. Draw 1 Card.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/QuickSlash.png",
    "game": "Slay the Spire",
    "tags": ["silent", "offense", "draw"]
  },
  {
    "name": "Slice",
    "rarity": "Common",
    "cost": 0,
    "type": "Attack",
    "description": "Deal 6 Dmg Melee.",
    "upgradedDescription": "Deal 9 Dmg Melee.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Slice.png",
    "game": "Slay the Spire",
    "tags": ["silent", "offense"]
  },
  {
    "name": "Sneaky Strike",
    "rarity": "Common",
    "cost": 2,
    "type": "Attack",
    "description": "Deal 12 Dmg Melee. If you have Discarded a Card this turn, Gain +2 Energy.",
    "upgradedDescription": "Deal 16 Dmg Melee. If you have Discarded a Card this turn, Gain +2 Energy.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/SneakyStrike.png",
    "game": "Slay the Spire",
    "tags": ["silent", "offense", "energy"]
  },
  {
    "name": "Sucker Punch",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 8 Dmg Melee. Inflict 1 Weak.",
    "upgradedDescription": "Deal 10 Dmg Melee. Inflict 2 Weak.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/SuckerPunch.png",
    "game": "Slay the Spire",
    "tags": ["silent", "offense", "debuff"]
  },
  {
    "name": "Unload",
    "rarity": "Rare",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 14 Dmg Ranged. Discard All non-Attack Cards in your hand.",
    "upgradedDescription": "Deal 18 Dmg Ranged. Discard All non-Attack Cards in your hand.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Unload.png",
    "game": "Slay the Spire",
    "tags": ["silent", "offense", "discard"]
  }
];
