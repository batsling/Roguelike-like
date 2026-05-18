// Auto-generated from Roguelikes.xlsx - Cards
// Card deck system: players build a deck from this pool

const CARDS_DATA = [
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
    "name": "Alchemize",
    "rarity": "Rare",
    "cost": 1,
    "type": "Skill",
    "description": "Gain 1 Random Potion Item. Exhaust.",
    "upgradedDescription": "Gain 1 Random Potion Item. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Alchemize.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "item"
    ]
  },
  {
    "name": "All for One",
    "rarity": "Rare",
    "cost": 2,
    "type": "Attack",
    "description": "Deal 10 Dmg Melee. Put all 0 cost Cards from Discard to Hand.",
    "upgradedDescription": "Deal 14 Dmg Melee. Put all 0 cost Cards from Discard to Hand.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/AllForOne.png",
    "game": "Slay the Spire",
    "tags": [
      "defect",
      "draw",
      "offense"
    ]
  },
  {
    "name": "All-Out Attack",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 10 Dmg Melee Cleave. Discard 1 Random Card.",
    "upgradedDescription": "Deal 14 Dmg Melee Cleave. Discard 1 Random Card.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/All-OutAttack.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense",
      "aoe",
      "discard"
    ]
  },
  {
    "name": "Anger",
    "rarity": "Common",
    "cost": 0,
    "type": "Attack",
    "description": "Deal 6 Dmg Melee. Conjure 1 copy of this card to Discard.",
    "upgradedDescription": "Deal 8 Dmg Melee. Conjure 1 copy of this card to Discard.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Anger.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense"
    ]
  },
  {
    "name": "Armaments",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Gain +5 Block. Upgrade a Card in your hand for the rest of combat.",
    "upgradedDescription": "Gain +5 Block. Upgrade all Cards in your hand for the rest of combat.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Armaments.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "defense"
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
    "name": "Backstab",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Attack",
    "description": "Innate. Deal 11 Dmg Melee. Exhaust.",
    "upgradedDescription": "Innate. Deal 15 Dmg Melee. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Backstab.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense",
      "exhaust"
    ]
  },
  {
    "name": "Bag o' Glitter",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Inflict 2 Blind. 10% chance to Exhaust.",
    "upgradedDescription": "Inflict 2 Blind. 10% chance to Exhaust.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/items/BagO'Glitter.png",
    "game": "Mewgenics",
    "tags": [
      "weapon",
      "debuff",
      "exhaust"
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
    "tags": [
      "silent",
      "offense",
      "debuff"
    ]
  },
  {
    "name": "Barrel",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 6 Dmg Ranged. Fishing Weight.",
    "upgradedDescription": "Deal 6 Dmg Ranged. Fishing Weight.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/items/Barrel.png",
    "game": "Enter the Gungeon",
    "tags": [
      "weapon"
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
    "name": "Battle Trance",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Skill",
    "description": "Draw 3 Cards. Gain +1 No Draw.",
    "upgradedDescription": "Draw 4 Cards. Gain +1 No Draw.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/BattleTrance.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "draw"
    ]
  },
  {
    "name": "Beam Cell",
    "rarity": "Common",
    "cost": 0,
    "type": "Attack",
    "description": "Deal 3 Dmg Ranged. Inflict 1 Vulnerable.",
    "upgradedDescription": "Deal 4 Dmg Ranged. Inflict 2 Vulnerable.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/BeamCell.png",
    "game": "Slay the Spire",
    "tags": [
      "defect",
      "offense",
      "debuff"
    ]
  },
  {
    "name": "Berserk",
    "rarity": "Rare",
    "cost": 0,
    "type": "Power",
    "description": "Gain 2 Vulnerable. At the start of your turn, Gain +1 Energy.",
    "upgradedDescription": "Gain 1 Vulnerable. At the start of your turn, Gain +1 Energy.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Berserk.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "energy"
    ]
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
    "tags": [
      "silent",
      "offense"
    ]
  },
  {
    "name": "Blasma Pistol",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 5 Dmg Ranged. Wealth.",
    "upgradedDescription": "Deal 5 Dmg Ranged. Wealth.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/items/BlasmaPistol.png",
    "game": "Flinthook",
    "tags": [
      "weapon"
    ]
  },
  {
    "name": "Blood for Blood",
    "rarity": "Uncommon",
    "cost": 4,
    "type": "Attack",
    "description": "Costs 1 less Energy for each time you lost Health this combat. Deal 18 Dmg Melee.",
    "upgradedDescription": "Costs 1 less Energy for each time you lost Health this combat. Deal 22 Dmg Melee.",
    "upgradedCost": 3,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/BloodForBlood.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "draw"
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
    "imageUrl": "images/items/BloodMagic.png",
    "game": "Megabonk",
    "tags": [
      "weapon"
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
    "name": "Bludgeon",
    "rarity": "Rare",
    "cost": 3,
    "type": "Attack",
    "description": "Deal 32 Dmg Melee.",
    "upgradedDescription": "Deal 42 Dmg Melee.",
    "upgradedCost": 3,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Bludgeon.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense"
    ]
  },
  {
    "name": "Blue Pigment",
    "rarity": "None",
    "cost": 1,
    "type": "Status",
    "description": "Gain +2 Arcane until end of the turn. At the end of your turn, if this is in Hand, Take 3 Dmg. Exhaust.",
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
    "name": "Blur",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Gain +5 Block. Gain 1 Blur",
    "upgradedDescription": "Gain +8 Block. Gain 1 Blur",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Blur.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "defense"
    ]
  },
  {
    "name": "Body Slam",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal X Dmg Melee, where X is equal to your current Block.",
    "upgradedDescription": "Deal X Dmg Melee, where X is equal to your current Block.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/BodySlam.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense"
    ]
  },
  {
    "name": "Boot Sequence",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Skill",
    "description": "Innate. Gain 10 Block. Exhaust",
    "upgradedDescription": "Innate. Gain 13 Block. Exhaust",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/BootSequence.png",
    "game": "Slay the Spire",
    "tags": [
      "defect",
      "defense",
      "exhaust"
    ]
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
    "name": "Bouncing Flask",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Skill",
    "description": "Inflict 3 Poison to a Random target. Repeat 2 times.",
    "upgradedDescription": "Inflict 3 Poison on Random target. Repeat 3 times.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/BouncingFlask.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "debuff"
    ]
  },
  {
    "name": "Brutality",
    "rarity": "Rare",
    "cost": 0,
    "type": "Power",
    "description": "At the start of your turn, Lose 1 Health and Draw 1 Card.",
    "upgradedDescription": "Innate. At the start of your turn, Lose 1 Health and Draw 1 Card.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Brutality.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "draw"
    ]
  },
  {
    "name": "Buffer",
    "rarity": "Rare",
    "cost": 2,
    "type": "Power",
    "description": "Gain +1 Buffer.",
    "upgradedDescription": "Gain +2 Buffer.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Buffer.png",
    "game": "Slay the Spire",
    "tags": [
      "defect",
      "defense"
    ]
  },
  {
    "name": "Bullet Time",
    "rarity": "Rare",
    "cost": 3,
    "type": "Skill",
    "description": "Gain +1 No Draw. All Cards in your Hand are free to play this turn.",
    "upgradedDescription": "Gain +1 No Draw. All Cards in your Hand are free to play this turn.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/BulletTime.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "energy"
    ]
  },
  {
    "name": "Burn",
    "rarity": "None",
    "cost": 0,
    "type": "Status",
    "description": "Unplayable. At the end of your turn, take 2 Dmg.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": true,
    "imageUrl": "images/cards/Burn.png",
    "game": "Slay the Spire",
    "tags": []
  },
  {
    "name": "Burning Pact",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Exhaust 1 Card. Draw 2 Cards.",
    "upgradedDescription": "Exhaust 1 Card. Draw 3 Cards.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/BurningPact.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "draw",
      "exhaust"
    ]
  },
  {
    "name": "Burst",
    "rarity": "Rare",
    "cost": 1,
    "type": "Skill",
    "description": "Until the end of the turn, Gain +1 Burst.",
    "upgradedDescription": "Until the end of the turn, Gain +2 Burst.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Burst.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "energy"
    ]
  },
  {
    "name": "Calculated Gamble",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Skill",
    "description": "Discard your hand, then Draw X Cards where X was the amount of cards that were Discarded. Exhaust",
    "upgradedDescription": "Discard your hand, then Draw X Cards where X was the amount of cards that were Discarded.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/CalculatedGamble.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "discard",
      "draw"
    ]
  },
  {
    "name": "Caltrops",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "Gain +3 Thorns",
    "upgradedDescription": "Gain +5 Thorns",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Caltrops.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "defense"
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
    "name": "Catalyst",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Inflict Double Poison. Exhaust.",
    "upgradedDescription": "Inflict Triple Poison. Exhaust.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Catalyst.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "debuff"
    ]
  },
  {
    "name": "Choke",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Attack",
    "description": "Deal 12 Dmg Melee. Inflict 3 Choked.",
    "upgradedDescription": "Deal 12 Dmg Melee. Inflict 5 Choked.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Choke.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "debuff",
      "offense"
    ]
  },
  {
    "name": "Clash",
    "rarity": "Common",
    "cost": 0,
    "type": "Attack",
    "description": "Can only be played if every Card in your Hand is an Attack. Deal 14 Dmg Melee.",
    "upgradedDescription": "Can only be played if every Card in your Hand is an Attack. Deal 18 Dmg Melee.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Clash.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense"
    ]
  },
  {
    "name": "Claw",
    "rarity": "Common",
    "cost": 0,
    "type": "Attack",
    "description": "Deal 3 Dmg Melee. Increase the Dmg of ALL Claw Cards by 2 this combat.",
    "upgradedDescription": "Deal 4 Dmg Melee. Increase the damage of ALL Claw cards by 3 this combat.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Claw.png",
    "game": "Slay the Spire",
    "tags": [
      "defect",
      "offense",
      "scaling"
    ]
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
    "name": "Cloak and Dagger",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Gain 6 Block. Conjure 1 Shiv to Hand.",
    "upgradedDescription": "Gain 6 Block. Conjure 2 Shivs to Hand.",
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
    "name": "Clumsy",
    "rarity": "None",
    "cost": 0,
    "type": "Curse",
    "description": "Unplayable. Ethereal.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": false,
    "imageUrl": "images/cards/Clumsy.png",
    "game": "Slay the Spire",
    "tags": [
      "randomcurse"
    ]
  },
  {
    "name": "Clumsy Die",
    "rarity": "Common",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/heroes/Clumsy.png",
    "game": "Slice & Dice ",
    "tags": [
      "hero",
      "orange"
    ]
  },
  {
    "name": "Combust",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "At the end of your turn, Lose 1 Health and Deal 5 Magic Dmg Fire Ranged Cleave.",
    "upgradedDescription": "At the end of your turn, Lose 1 Health and Deal 7 Magic Dmg Fire Ranged Cleave.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Combust.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense"
    ]
  },
  {
    "name": "Concentrate",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Skill",
    "description": "Discard 3 Cards. Gain +2 Energy.",
    "upgradedDescription": "Discard 2 Cards. Gain +2 Energy.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Concentrate.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "discard",
      "energy"
    ]
  },
  {
    "name": "Corpse Explosion",
    "rarity": "Rare",
    "cost": 2,
    "type": "Skill",
    "description": "Inflict 6 Poison. Inflict 1 Corpse Explosion.",
    "upgradedDescription": "Inflict 9 Poison. Inflict 1 Corpse Explosion.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/CorpseExplosion.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "debuff",
      "aoe"
    ]
  },
  {
    "name": "Corruption",
    "rarity": "Rare",
    "cost": 3,
    "type": "Power",
    "description": "Skills cost 0 Energy. Whenever you play a Skill, Exhaust it.",
    "upgradedDescription": "Skills cost 0 Energy. Whenever you play a Skill, Exhaust it.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Corruption.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "energy"
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
    "name": "Dabblest",
    "rarity": "Rare",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Dabblest.png",
    "game": "Slice & Dice ",
    "tags": [
      "hero",
      "orange"
    ]
  },
  {
    "name": "Dagger Spray",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 4x2 Dmg Ranged Cleave.",
    "upgradedDescription": "Deal 6x2 Dmg Ranged Cleave.",
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
    "tags": [
      "silent",
      "offense",
      "discard",
      "draw"
    ]
  },
  {
    "name": "Dark Embrace",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Power",
    "description": "Whenever a Card is Exhausted, Draw 1 Card.",
    "upgradedDescription": "Whenever a Card is Exhausted, Draw 1 Card.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/DarkEmbrace.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "draw",
      "exhaust"
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
    "name": "Dazed",
    "rarity": "None",
    "cost": 0,
    "type": "Status",
    "description": "Ethereal.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": true,
    "imageUrl": "images/cards/Dazed.png",
    "game": "Slay the Spire",
    "tags": []
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
    "name": "Decay",
    "rarity": "None",
    "cost": 0,
    "type": "Curse",
    "description": "Unplayable. At the end of your turn, if this is in your Hand, it deals 2 Dmg to you.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": false,
    "imageUrl": "images/cards/Decay.png",
    "game": "Slay the Spire",
    "tags": [
      "randomcurse"
    ]
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
    "name": "Defender",
    "rarity": "Common",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Defender.png",
    "game": "Slice & Dice ",
    "tags": [
      "hero",
      "gray"
    ]
  },
  {
    "name": "Deflect",
    "rarity": "Common",
    "cost": 0,
    "type": "Skill",
    "description": "Gain +4 Block.",
    "upgradedDescription": "Gain +7 Block",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Deflect.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "defense"
    ]
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
    "name": "Dexecutioner",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Attack",
    "description": "6 Assassinate.",
    "upgradedDescription": "6 Assassinate.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/items/Dexecutioner.png",
    "game": "Megabonk",
    "tags": [
      "weapon"
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
      "aoe",
      "exhaust"
    ]
  },
  {
    "name": "Disarm",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Inflict -2 Power. Exhaust.",
    "upgradedDescription": "Inflict -3 Power. Exhaust.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Disarm.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "debuff",
      "exhaust"
    ]
  },
  {
    "name": "Distraction",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Conjure 1 Random Skill in Hand. You can play it for free this turn. Exhaust.",
    "upgradedDescription": "Conjure 1 Random Skill in Hand. You can play it for free this turn. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Distraction.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "draw",
      "random"
    ]
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
    "tags": [
      "silent",
      "defense"
    ]
  },
  {
    "name": "Doppelganger",
    "rarity": "Rare",
    "cost": "X",
    "type": "Skill",
    "description": "Gain X Next Turn Draw and Gain X Next Turn Energy. Exhaust.",
    "upgradedDescription": "Gain X+1 Next Turn Draw and Gain X+1 Next Turn Energy. Exhaust.",
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
    "name": "Double Tap",
    "rarity": "Rare",
    "cost": 1,
    "type": "Skill",
    "description": "This turn, your next Attack is played twice.",
    "upgradedDescription": "This turn, your next 2 Attacks are played twice.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/DoubleTap.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "energy",
      "offense"
    ]
  },
  {
    "name": "Doubt",
    "rarity": "None",
    "cost": 0,
    "type": "Curse",
    "description": "Unplayable. At the end of your turn, Gain 1 Weak.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": false,
    "imageUrl": "images/cards/Doubt.png",
    "game": "Slay the Spire",
    "tags": [
      "randomcurse"
    ]
  },
  {
    "name": "Dropkick",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 5 Dmg Melee. If the target has Vulnerable, Gain +1 Energy and Draw 1 Card",
    "upgradedDescription": "Deal 8 Dmg Melee. If the target has Vulnerable, Gain +1 Energy and Draw 1 Card",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Dropkick.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "draw",
      "energy"
    ]
  },
  {
    "name": "Druid",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die. When adding this Card to your Deck, Learn Balance.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll. When adding this Card to your Deck, Learn Balance.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Druid.png",
    "game": "Slice & Dice ",
    "tags": [
      "hero",
      "red"
    ]
  },
  {
    "name": "Dual Weild",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Choose an Attack or Power Card. Conjure 1 Copy of that Card to Hand.",
    "upgradedDescription": "Choose an Attack or Power Card. Conjure 2 Copies of that Card to Hand.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/DualWield.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "draw"
    ]
  },
  {
    "name": "Endless Agony",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Attack",
    "description": "Whenever you draw this card, Conjure X in Deck where X is a copy of this card. Deal 4 Dmg Melee. Exhaust.",
    "upgradedDescription": "Whenever you draw this card, Conjure X in Deck where X is a copy of this card. Deal 6 Dmg Melee. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/EndlessAgony.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense"
    ]
  },
  {
    "name": "Entrench",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Skill",
    "description": "Gain Double Block.",
    "upgradedDescription": "Gain Double Block.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Entrench.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "defense"
    ]
  },
  {
    "name": "Envenom",
    "rarity": "Rare",
    "cost": 2,
    "type": "Power",
    "description": "Gain +1 Envenom.",
    "upgradedDescription": "Gain +1 Envenom.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Envenom.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "debuff",
      "offense"
    ]
  },
  {
    "name": "Escape Plan",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Skill",
    "description": "Draw 1 Card. If it was a Skill, Gain +3 Block.",
    "upgradedDescription": "Draw 1 Card. If it was a Skill, Gain +5 Block.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/EscapePlan.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "draw",
      "defense"
    ]
  },
  {
    "name": "Eviscerate",
    "rarity": "Uncommon",
    "cost": 3,
    "type": "Attack",
    "description": "Costs 1 less Energy for each Discarded Card this turn. Deal 7x3 Dmg Melee.",
    "upgradedDescription": "Costs 1 less Energy for each Discarded Card this turn. Deal 9x3 Dmg Melee.",
    "upgradedCost": 3,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Eviscerate.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense",
      "discard"
    ]
  },
  {
    "name": "Evolve",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "Gain +1 Evolve.",
    "upgradedDescription": "Gain +2 Evolve.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Evolve.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "draw",
      "status"
    ]
  },
  {
    "name": "Exhume",
    "rarity": "Rare",
    "cost": 1,
    "type": "Skill",
    "description": "Put 1 Card from your Exhaust to your Hand. Exhaust.",
    "upgradedDescription": "Put 1 Card from your Exhaust to your Hand. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Exhume.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "exhaust"
    ]
  },
  {
    "name": "Expertise",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Draw X Cards where X is equal to 6 - the amount of Cards in your Hand.",
    "upgradedDescription": "Draw X Cards where X is equal to 7 - the amount of Cards in your Hand.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Expertise.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "draw"
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
      "health",
      "exhaust"
    ]
  },
  {
    "name": "Feel No Pain",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "Gain +3 Feel No Pain.",
    "upgradedDescription": "Gain +4 Feel No Pain.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/FeelNoPain.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "defense",
      "exhaust"
    ]
  },
  {
    "name": "Fiend Fire",
    "rarity": "Rare",
    "cost": 2,
    "type": "Attack",
    "description": "Exhaust All Cards in Hand. Deal 7xX Dmg Ranged where X is equal to the amount of Cards Exhausted. Exhaust.",
    "upgradedDescription": "Exhaust All Cards in Hand. Deal 10xX Dmg Ranged where X is equal to the amount of Cards Exhausted. Exhaust.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/FiendFire.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "exhaust"
    ]
  },
  {
    "name": "Fighter",
    "rarity": "Common",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Fighter.png",
    "game": "Slice & Dice",
    "tags": [
      "hero",
      "yellow"
    ]
  },
  {
    "name": "Finisher",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 6xX Dmg Melee where X is equal to the amount of Attacks played this turn.",
    "upgradedDescription": "Deal 8xX Dmg Melee where X is equal to the amount of Attacks played this turn.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Finisher.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense"
    ]
  },
  {
    "name": "Fire Breathing",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "Gain +6 Fire Breathing.",
    "upgradedDescription": "Gain +10 Fire Breathing.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/FireBreathing.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "aoe",
      "status"
    ]
  },
  {
    "name": "Flame Barrier",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Skill",
    "description": "Gain +12 Block. Gain +4 Flame Barrier.",
    "upgradedDescription": "Gain +16 Block. Gain +6 Flame Barrier.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/FlameBarrier.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "defense"
    ]
  },
  {
    "name": "Flechettes",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 4xX Dmg Ranged where X is equal to the amount of Skills in your Hand.",
    "upgradedDescription": "Deal 6xX Dmg Ranged where X is equal to the amount of Skills in your Hand.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Flechettes.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense"
    ]
  },
  {
    "name": "Flex",
    "rarity": "Common",
    "cost": 0,
    "type": "Skill",
    "description": "Until the end of the turn, Gain +2 Power.",
    "upgradedDescription": "Until the end of the turn, Gain +4 Power.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Flex.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense"
    ]
  },
  {
    "name": "Flying Knee",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 8 Dmg Melee. Gain +1 Next Turn Energy.",
    "upgradedDescription": "Deal 11 Dmg Melee. Gain +1 Next Turn Energy.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/FlyingKnee.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense",
      "energy"
    ]
  },
  {
    "name": "Footwork",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "Gain +2 Defense",
    "upgradedDescription": "Gain +3 Defense",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Footwork.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "defense"
    ]
  },
  {
    "name": "Gambler",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Gambler.png",
    "game": "Slice & Dice",
    "tags": [
      "hero",
      "orange"
    ]
  },
  {
    "name": "Ghostly Armor",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Ethereal. Gain +10 Block.",
    "upgradedDescription": "Ethereal. Gain +13 Block.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/GhostlyArmor.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "defense"
    ]
  },
  {
    "name": "Gladiator",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Gladiator.png",
    "game": "Slice & Dice",
    "tags": [
      "hero",
      "yellow"
    ]
  },
  {
    "name": "Glass Knife",
    "rarity": "Rare",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 8x2 Dmg Melee. Decrease the Dmg of this Card by 2 this combat.",
    "upgradedDescription": "Deal 12x2 Dmg Melee. Decrease the Dmg of this Card by 2 this combat.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/GlassKnife.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense"
    ]
  },
  {
    "name": "Go for the Eyes",
    "rarity": "Common",
    "cost": 0,
    "type": "Attack",
    "description": "Deal 3 Dmg Melee. If target intends to attack, Inflict 1 Weak.",
    "upgradedDescription": "Deal 4 Dmg Melee. If target intends to attack, Inflict 2 Weak.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/GoForTheEyes.png",
    "game": "Slay the Spire",
    "tags": [
      "defect",
      "offense",
      "debuff"
    ]
  },
  {
    "name": "Grand Finale",
    "rarity": "Rare",
    "cost": 0,
    "type": "Attack",
    "description": "Can only be played if there are no cards in your draw pile. Deal 50 Dmg Ranged Cleave.",
    "upgradedDescription": "Can only be played if there are no cards in your draw pile. Deal 60 Dmg Ranged Cleave.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/GrandFinale.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense"
    ]
  },
  {
    "name": "Guilty",
    "rarity": "None",
    "cost": 0,
    "type": "Curse",
    "description": "Unplayable. Destroy after completing 3 Combats.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": false,
    "imageUrl": "images/cards/Guilty.png",
    "game": "Slay the Spire 2",
    "tags": [
      "randomcurse"
    ]
  },
  {
    "name": "Havoc",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Play the top card of your Draw Pile and Exhaust it.",
    "upgradedDescription": "Play the top card of your Draw Pile and Exhaust it.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Havoc.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "exhaust"
    ]
  },
  {
    "name": "Headbutt",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 9 Dmg Melee. Put a Card from your Discard on the top of the Draw Pile.",
    "upgradedDescription": "Deal 12 Dmg Melee. Put a Card from your Discard on the top of the Draw Pile.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Headbutt.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense"
    ]
  },
  {
    "name": "Healer",
    "rarity": "Common",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die. When adding this Card to your Deck, Learn Mend.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll. When adding this Card to your Deck, Learn Mend.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Healer.png",
    "game": "Slice & Dice",
    "tags": [
      "hero",
      "red"
    ]
  },
  {
    "name": "Heavy Blade",
    "rarity": "Common",
    "cost": 2,
    "type": "Attack",
    "description": "Deal 14 Dmg Melee. Power affects this card x3 times.",
    "upgradedDescription": "Deal 14 Dmg Melee. Power affects this card x5 times.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/HeavyBlade.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "scaling"
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
    "name": "Hemokinesis",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Attack",
    "description": "Lose 2 Health. Deal 15 Dmg Ranged.",
    "upgradedDescription": "Lose 2 Health. Deal 20 Dmg Ranged.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Hemokinesis.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense"
    ]
  },
  {
    "name": "Hologram",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Gain +3 Block. Put a Card from Discard to Hand. Exhaust.",
    "upgradedDescription": "Gain +5 Block. Put a Card from Discard to Hand.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Hologram.png",
    "game": "Slay the Spire",
    "tags": [
      "defect",
      "defense",
      "draw",
      "exhaust"
    ]
  },
  {
    "name": "Immolate",
    "rarity": "Rare",
    "cost": 2,
    "type": "Attack",
    "description": "Deal 21 Magic Dmg Fire Cleave. Conjure 1 Burn to Discard.",
    "upgradedDescription": "Deal 28 Magic Dmg Fire Cleave. Conjure 1 Burn to Discard.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Immolate.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense"
    ]
  },
  {
    "name": "Impervious",
    "rarity": "Rare",
    "cost": 2,
    "type": "Skill",
    "description": "Gain +30 Block. Exhaust.",
    "upgradedDescription": "Gain +40 Block. Exhaust.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Impervious.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "defense",
      "exhaust"
    ]
  },
  {
    "name": "Infernal Blade",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Conjure 1 Random Attack in Hand. You can play it for free this turn. Exhaust.",
    "upgradedDescription": "Conjure 1 Random Attack in Hand. You can play it for free this turn. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/InfernalBlade.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "draw",
      "random"
    ]
  },
  {
    "name": "Infinite Blades",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "At the start of your turn, Conjure 1 Shiv to Hand.",
    "upgradedDescription": "Innate. At the start of your turn, Conjure 1 Shiv to Hand.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/InfiniteBlades.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
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
    "name": "Injury",
    "rarity": "None",
    "cost": 0,
    "type": "Curse",
    "description": "Unplayable.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": false,
    "imageUrl": "images/cards/Injury.png",
    "game": "Slay the Spire",
    "tags": [
      "randomcurse"
    ]
  },
  {
    "name": "Intimidate",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Skill",
    "description": "Inflict 1 Weak Cleave. Exhaust.",
    "upgradedDescription": "Inflict 2 Weak Cleave. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Intimidate.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "debuff",
      "exhaust"
    ]
  },
  {
    "name": "Iron Wave",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Gain +5 Block. Deal 5 Dmg Ranged.",
    "upgradedDescription": "Gain +7 Block. Deal 7 Dmg Ranged.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/IronWave.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "defense"
    ]
  },
  {
    "name": "Isaac's D6",
    "rarity": "Starter",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die. Choose a Card in your Hand, it transforms into a random Card of the rolled type.",
    "upgradedDescription": "Roll this die. Choose a Card in your Hand, it transforms into a random Card of the rolled type.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": null,
    "game": "The Binding of Isaac",
    "tags": []
  },
  {
    "name": "Jester",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die. When adding this Card to your Deck, Learn Flick.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll. When adding this Card to your Deck, Learn Flick.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Jester.png",
    "game": "Slice & Dice",
    "tags": [
      "hero",
      "blue"
    ]
  },
  {
    "name": "Juggernaut",
    "rarity": "Rare",
    "cost": 2,
    "type": "Power",
    "description": "Whenever you Gain Block, Deal 5 Dmg Melee to a random enemy.",
    "upgradedDescription": "Whenever you Gain Block, Deal 7 Dmg Melee to a random enemy.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Juggernaut.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "defense"
    ]
  },
  {
    "name": "Juggler",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Juggler.png",
    "game": "Slice & Dice",
    "tags": [
      "hero",
      "orange"
    ]
  },
  {
    "name": "Lazy",
    "rarity": "Common",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Lazy.png",
    "game": "Slice & Dice",
    "tags": [
      "hero",
      "yellow"
    ]
  },
  {
    "name": "Leap",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Gain +9 Block.",
    "upgradedDescription": "Gain +12 Block.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Leap.png",
    "game": "Slay the Spire",
    "tags": [
      "defect",
      "defense"
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
    "name": "Lil' Bomber",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 5 Dmg Ranged.",
    "upgradedDescription": "Deal 5 Dmg Ranged.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/items/LilBomber.png",
    "game": "Enter the Gungeon",
    "tags": [
      "weapon"
    ]
  },
  {
    "name": "Limit Break",
    "rarity": "Rare",
    "cost": 1,
    "type": "Skill",
    "description": "Gain Double Power. Exhaust.",
    "upgradedDescription": "Gain Double Power.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/LimitBreak.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "scaling"
    ]
  },
  {
    "name": "Machine Learning",
    "rarity": "Rare",
    "cost": 1,
    "type": "Power",
    "description": "At the start of your turn, Gain +1 Next Turn Draw. ",
    "upgradedDescription": "Innate. At the start of your turn, Gain +1 Next Turn Draw. ",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/MachineLearning.png",
    "game": "Slay the Spire",
    "tags": [
      "defect",
      "draw"
    ]
  },
  {
    "name": "Mage",
    "rarity": "Common",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die. When adding this Card to your Deck, Learn Poke.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll. When adding this Card to your Deck, Learn Poke.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Mage.png",
    "game": "Slice & Dice",
    "tags": [
      "hero",
      "blue"
    ]
  },
  {
    "name": "Malaise",
    "rarity": "Rare",
    "cost": "X",
    "type": "Skill",
    "description": "Inflict -X Power and Inflict X Weak. Exhaust",
    "upgradedDescription": "Inflict -X-1 Power and Inflict X+1 Weak. Exhaust",
    "upgradedCost": "X",
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Malaise.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "debuff",
      "exhaust"
    ]
  },
  {
    "name": "Masterful Stab",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Attack",
    "description": "Costs 1 more Energy for each time you've lost Health this combat. Deal 12 Dmg Melee.",
    "upgradedDescription": "Costs 1 more Energy for each time you've lost Health this combat. Deal 16 Dmg Melee.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/MasterfulStab.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense"
    ]
  },
  {
    "name": "Metallicize",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "At the end of your turn, Gain +3 Block.",
    "upgradedDescription": "At the end of your turn, Gain +4 Block.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Metallicize.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "defense"
    ]
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
    "name": "Mystic",
    "rarity": "Common",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die. When adding this Card to your Deck, Learn Gaze.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll. When adding this Card to your Deck, Learn Gaze.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Mystic.png",
    "game": "Slice & Dice",
    "tags": [
      "hero",
      "red"
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
    "name": "Nightmare",
    "rarity": "Rare",
    "cost": 3,
    "type": "Skill",
    "description": "Choose a Card. Next turn, Conjure 3 copies of that Card to your Hand.",
    "upgradedDescription": "Choose a Card. Next turn, Conjure 3 copies of that Card to your Hand.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Nightmare.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "draw"
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
    "name": "Offering",
    "rarity": "Rare",
    "cost": 0,
    "type": "Skill",
    "description": "Lose 6 Health. Gain +2 Energy. Draw 3 Cards. Exhaust.",
    "upgradedDescription": "Lose 6 Health. Gain +2 Energy. Draw 5 Cards. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Offering.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "energy",
      "draw",
      "exhaust"
    ]
  },
  {
    "name": "Outmaneuver",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Gain +2 Next Turn Energy.",
    "upgradedDescription": "Gain +3 Next Turn Energy.",
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
    "name": "Pain",
    "rarity": "None",
    "cost": 0,
    "type": "Curse",
    "description": "Unplayable. If this is in Hand, Lose 1 Health when playing another Card. ",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": false,
    "imageUrl": "images/cards/Pain.png",
    "game": "Slay the Spire",
    "tags": [
      "randomcurse"
    ]
  },
  {
    "name": "Perfected Strike",
    "rarity": "Common",
    "cost": 2,
    "type": "Attack",
    "description": "Deal 6 Dmg Melee. Deals 2 additional damage for All of your Cards that contain \"Strike\".",
    "upgradedDescription": "Deal 6 Dmg Melee. Deals 3 additional damage for All of your Cards that contain \"Strike\".",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/PerfectedStrike.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense"
    ]
  },
  {
    "name": "Phantasmal Killer",
    "rarity": "Rare",
    "cost": 1,
    "type": "Skill",
    "description": "Gain +1 Double Damage.",
    "upgradedDescription": "Gain +1 Double Damage.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/PhantasmalKiller.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense"
    ]
  },
  {
    "name": "Piercing Wail",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Inflict -6 Power Cleave and Inflict 6 Shackled Cleave. Exhaust.",
    "upgradedDescription": "Inflict -8 Power Cleave and Inflict 8 Shackled Cleave. Exhaust.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/PiercingWail.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "debuff",
      "exhaust"
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
    "name": "Power Through",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Conjure 2 Wounds to Hand. Gain +15 Block.",
    "upgradedDescription": "Conjure 2 Wounds to Hand. Gain +20 Block.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/PowerThrough.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "defense",
      "status"
    ]
  },
  {
    "name": "Predator",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Attack",
    "description": "Deal 15 Dmg Melee. Gain +2 Next Turn Draw.",
    "upgradedDescription": "Deal 20 Dmg Melee. Gain +2 Next Turn Draw.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Predator.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense",
      "energy"
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
    "name": "Pummel",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 2x4 Dmg Melee. Exhaust.",
    "upgradedDescription": "Deal 2x5 Dmg Melee. Exhaust.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Pummel.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "exhaust"
    ]
  },
  {
    "name": "Punctured Eye",
    "rarity": "None",
    "cost": 0,
    "type": "Curse",
    "description": "Unplayable. At the end of your turn, if this is in Hand, Gain 1 Blind.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": false,
    "imageUrl": "images/cards/PuncturedEye.png",
    "game": "Mewgenics",
    "tags": []
  },
  {
    "name": "Purple Pigment",
    "rarity": "None",
    "cost": 1,
    "type": "Status",
    "description": "Gain +1 Persistence until end of the turn. At the end of your turn, if this is in Hand, Take 3 Dmg. Exhaust.",
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
    "tags": [
      "silent",
      "offense",
      "draw"
    ]
  },
  {
    "name": "Rage",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Skill",
    "description": "Until the end of your turn, whenever you play an Attack, Gain +3 Block.",
    "upgradedDescription": "Until the end of your turn, whenever you play an Attack, Gain +5 Block.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Rage.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "defense"
    ]
  },
  {
    "name": "Rampage",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 8 Dmg Melee. Increase the Dmg of this Card by 5 this combat.",
    "upgradedDescription": "Deal 8 Dmg Melee. Increase the Dmg of this Card by 8 this combat.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Rampage.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "scaling"
    ]
  },
  {
    "name": "Ranger",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Ranger.png",
    "game": "Slice & Dice",
    "tags": [
      "hero",
      "orange"
    ]
  },
  {
    "name": "Reaper",
    "rarity": "Rare",
    "cost": 2,
    "type": "Attack",
    "description": "Deal 4 Dmg Melee Cleave Lifesteal. Exhaust.",
    "upgradedDescription": "Deal 5 Dmg Melee Cleave Lifesteal. Exhaust.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Reaper.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "health",
      "exhaust"
    ]
  },
  {
    "name": "Reckless Charge",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Attack",
    "description": "Deal 7 Dmg Melee. Conjure 1 Dazed to Deck. ",
    "upgradedDescription": "Deal 10 Dmg Melee. Conjure 1 Dazed to Deck. ",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/RecklessCharge.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "status"
    ]
  },
  {
    "name": "Red Pigment",
    "rarity": "None",
    "cost": 1,
    "type": "Status",
    "description": "Gain +2 Power until end of the turn. At the end of your turn, if this is in Hand, Take 3 Dmg. Exhaust.",
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
    "name": "Reflex",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Skill",
    "description": "Sly. Draw 2 Cards.",
    "upgradedDescription": "Sly. Draw 3 Cards.",
    "upgradedCost": null,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Reflex.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "discard",
      "draw"
    ]
  },
  {
    "name": "Regret",
    "rarity": "None",
    "cost": 0,
    "type": "Curse",
    "description": "Unplayable. At the end of your turn, if this is in Hand, Lose 1 Health for each card in Hand.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": false,
    "imageUrl": "images/cards/Regret.png",
    "game": "Slay the Spire",
    "tags": [
      "randomcurse"
    ]
  },
  {
    "name": "Riddle with Holes",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Attack",
    "description": "Deal 3x5 Dmg Melee.",
    "upgradedDescription": "Deal 4x5 Dmg Melee.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/RiddleWithHoles.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "offense"
    ]
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
    "name": "Rupture",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "Whenever you lose Health from a Card, Gain +1 Power.",
    "upgradedDescription": "Whenever you lose Health from a Card, Gain +2 Power.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Rupture.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "scaling"
    ]
  },
  {
    "name": "Rusty Razor",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Inflict 1 Bleed and 1 Poison.",
    "upgradedDescription": "Inflict 1 Bleed and 1 Poison.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/items/RustyRazor.png",
    "game": "Mewgenics",
    "tags": [
      "weapon"
    ]
  },
  {
    "name": "Searing Blow",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Attack",
    "description": "Deal 12 Magic Dmg Fire Melee. Sequential Upgrade Magic Dmg +3.",
    "upgradedDescription": null,
    "upgradedCost": 2,
    "canUpgrade": false,
    "isStatusCard": false,
    "imageUrl": "images/cards/SearingBlow.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "scaling"
    ]
  },
  {
    "name": "Second Wind",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Exhaust all non-Attack Cards in Hand. Gain +5 Block for each Card Exhausted.",
    "upgradedDescription": "Exhaust all non-Attack Cards in Hand. Gain +7 Block for each Card Exhausted.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/SecondWind.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "defense",
      "exhaust"
    ]
  },
  {
    "name": "Seeing Red",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Gain 2 Energy. Exhaust.",
    "upgradedDescription": "Gain 2 Energy. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/SeeingRed.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "energy",
      "exhaust"
    ]
  },
  {
    "name": "Seek",
    "rarity": "Rare",
    "cost": 0,
    "type": "Skill",
    "description": "Put 1 Card from your Deck to Hand. Exhaust.",
    "upgradedDescription": "Put 2 Cards from your Deck to Hand. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Seek.png",
    "game": "Slay the Spire",
    "tags": [
      "defect",
      "draw",
      "exhaust"
    ]
  },
  {
    "name": "Sentinel",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Gain +5 Block. If this Card is Exhausted, Gain +2 Energy.",
    "upgradedDescription": "Gain +8 Block. If this Card is Exhausted, Gain +3 Energy.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Sentinel.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "defense",
      "exhaust"
    ]
  },
  {
    "name": "Setup",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Put 1 Card in your Hand on the top of the Draw Pile. It is free to play until played.",
    "upgradedDescription": "Put 1 Card in your Hand on the top of the Draw Pile. It is free to play until played.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Setup.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "energy"
    ]
  },
  {
    "name": "Sever Soul",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Attack",
    "description": "Exhaust all non-Attack Cards in Hand. Deal 16 Dmg.",
    "upgradedDescription": "Exhaust all non-Attack Cards in Hand. Deal 22 Dmg.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/SeverSoul.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "exhaust"
    ]
  },
  {
    "name": "Shame",
    "rarity": "None",
    "cost": 0,
    "type": "Curse",
    "description": "Unplayable. At the end of your turn, if this is in Hand, Gain 1 Frail.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": false,
    "imageUrl": "images/cards/Shame.png",
    "game": "Slay the Spire",
    "tags": [
      "randomcurse"
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
    "isStatusCard": false,
    "imageUrl": "images/cards/Shiv.png",
    "game": "Slay the Spire",
    "tags": []
  },
  {
    "name": "Shockwave",
    "rarity": "Uncommon",
    "cost": 2,
    "type": "Skill",
    "description": "Apply 3 Weak Cleave and 3 Vulnerable Cleave. Exhaust.",
    "upgradedDescription": "Apply 5 Weak Cleave and 5 Vulnerable Cleave. Exhaust.",
    "upgradedCost": 2,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Shockwave.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "debuff",
      "exhaust"
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
    "tags": [
      "silent",
      "offense"
    ]
  },
  {
    "name": "Slimed",
    "rarity": "None",
    "cost": 1,
    "type": "Status",
    "description": "Draw 1 Card. Exhaust.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": true,
    "imageUrl": "images/cards/Slimed.png",
    "game": "Slay the Spire",
    "tags": []
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
    "tags": [
      "silent",
      "offense",
      "energy"
    ]
  },
  {
    "name": "Soldier",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Soldier.png",
    "game": "Slice & Dice",
    "tags": [
      "hero",
      "yellow"
    ]
  },
  {
    "name": "Spot Weakness",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "If target enemy intends to attack, Gain +3 Power.",
    "upgradedDescription": "If target enemy intends to attack, Gain +4 Power.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/SpotWeakness.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "scaling"
    ]
  },
  {
    "name": "Storm of Steel",
    "rarity": "Rare",
    "cost": 1,
    "type": "Skill",
    "description": "Discard your Hand, then Conjure X Shivs where X was the amount of cards that were Discarded.",
    "upgradedDescription": "Discard your Hand, then Conjure X Upgraded Shivs where X was the amount of cards that were Discarded.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/StormOfShield.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "discard",
      "offense"
    ]
  },
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
    "name": "Sweeping Beam",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 6 Dmg Ranged Cleave. Draw 1 Card.",
    "upgradedDescription": "Deal 9 Dmg Ranged Cleave. Draw 1 Card.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/SweepingBeam.png",
    "game": "Slay the Spire",
    "tags": [
      "defect",
      "offense",
      "draw"
    ]
  },
  {
    "name": "Sword Boomerang",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 3 Dmg Ranged to a Random target. Repeat 2 times",
    "upgradedDescription": "Deal 3 Dmg Ranged to a Random target. Repeat 3 times",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/SwordBoomerang.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense"
    ]
  },
  {
    "name": "Tactician",
    "rarity": "Uncommon",
    "cost": 0,
    "type": "Skill",
    "description": "Sly. Gain +1 Energy.",
    "upgradedDescription": "Sly. Gain +2 Energy.",
    "upgradedCost": null,
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
    "name": "Terror",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Inflict 99 Vulnerable. Exhaust.",
    "upgradedDescription": "Inflict 99 Vulnerable. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Terror.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "debuff",
      "exhaust"
    ]
  },
  {
    "name": "Thunderclap",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 4 Dmg Ranged Cleave. Inflict 1 Vulnerable Cleave.",
    "upgradedDescription": "Deal 7 Dmg Ranged Cleave. Inflict 1 Vulnerable Cleave.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Thunderclap.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense",
      "debuff"
    ]
  },
  {
    "name": "Tools of the Trade",
    "rarity": "Rare",
    "cost": 1,
    "type": "Power",
    "description": "At the start of your turn, Draw 1 Card and Discard 1 Card.",
    "upgradedDescription": "At the start of your turn, Draw 1 Card and Discard 1 Card.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/ToolsOfTheTrade.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "draw",
      "discard"
    ]
  },
  {
    "name": "True Grit",
    "rarity": "Common",
    "cost": 1,
    "type": "Skill",
    "description": "Gain +7 Block. Exhaust a random Card in your Hand.",
    "upgradedDescription": "Gain +7 Block. Exhaust a Card in your Hand.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/TrueGrit.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "defense",
      "exhaust"
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
    "tags": [
      "silent",
      "offense",
      "discard"
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
    "name": "Veteran",
    "rarity": "Rare",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Veteran.png",
    "game": "Slice & Dice",
    "tags": [
      "hero",
      "yellow"
    ]
  },
  {
    "name": "Warcry",
    "rarity": "Common",
    "cost": 0,
    "type": "Skill",
    "description": "Draw 1 Card. Put a Card from your Hand on the top of the Draw Pile. Exhaust.",
    "upgradedDescription": "Draw 2 Cards. Put a Card from your Hand on the top of the Draw Pile. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Warcry.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "draw"
    ]
  },
  {
    "name": "Warden",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Dice",
    "description": "Roll this die.",
    "upgradedDescription": "Roll this die. Gain +1 Reroll.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Warden.png",
    "game": "Slice & Dice",
    "tags": [
      "hero",
      "gray"
    ]
  },
  {
    "name": "Well-Laid Plans",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Power",
    "description": "Gain +1 Well-Laid Plans.",
    "upgradedDescription": "Gain +2 Well-Laid Plans.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Well-LaidPlans.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "draw"
    ]
  },
  {
    "name": "Whirlwind",
    "rarity": "Uncommon",
    "cost": "X",
    "type": "Attack",
    "description": "Deal 5xX Dmg Cleave.",
    "upgradedDescription": "Deal 8xX Dmg Cleave.",
    "upgradedCost": "X",
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/Whirlwind.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "offense"
    ]
  },
  {
    "name": "White Noise",
    "rarity": "Uncommon",
    "cost": 1,
    "type": "Skill",
    "description": "Conjure 1 Random Power in Hand. You can play it for free this turn. Exhaust.",
    "upgradedDescription": "Conjure 1 Random Power in Hand. You can play it for free this turn. Exhaust.",
    "upgradedCost": 0,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/WhiteNoise.png",
    "game": "Slay the Spire",
    "tags": [
      "defect",
      "draw",
      "random",
      "exhaust"
    ]
  },
  {
    "name": "Wild Strike",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 12 Dmg Melee. Conjure 1 Wound to Draw.",
    "upgradedDescription": "Deal 17 Dmg Melee. Conjure 1 Wound to Draw.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/WildStrike.png",
    "game": "Slay the Spire",
    "tags": [
      "ironclad",
      "draw",
      "status"
    ]
  },
  {
    "name": "Wound",
    "rarity": "None",
    "cost": 0,
    "type": "Status",
    "description": "Unplayable.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": true,
    "imageUrl": "images/cards/Wound.png",
    "game": "Slay the Spire",
    "tags": []
  },
  {
    "name": "Wraith Form",
    "rarity": "Rare",
    "cost": 3,
    "type": "Power",
    "description": "Gain +2 Intangible. At the start of the turn, Lose 1 Defense.",
    "upgradedDescription": "Gain +3 Intangible. At the start of the turn, Lose 1 Defense.",
    "upgradedCost": 3,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/cards/WraithForm.png",
    "game": "Slay the Spire",
    "tags": [
      "silent",
      "defense"
    ]
  },
  {
    "name": "Writhe",
    "rarity": "None",
    "cost": 0,
    "type": "Curse",
    "description": "Unplayable. Innate.",
    "upgradedDescription": null,
    "upgradedCost": null,
    "canUpgrade": false,
    "isStatusCard": false,
    "imageUrl": "images/cards/Writhe.png",
    "game": "Slay the Spire",
    "tags": [
      "randomcurse"
    ]
  },
  {
    "name": "Yellow Pigment",
    "rarity": "None",
    "cost": 1,
    "type": "Status",
    "description": "Gain +2 Defense until end of the turn. At the end of your turn, if this is in Hand, Take 3 Dmg. Exhaust.",
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
    "name": "Lower Case r",
    "rarity": "Common",
    "cost": 1,
    "type": "Attack",
    "description": "Deal 5 Dmg Ranged.",
    "upgradedDescription": "Deal 5 Dmg Ranged.",
    "upgradedCost": 1,
    "canUpgrade": true,
    "isStatusCard": false,
    "imageUrl": "images/items/LowerCaseR.png",
    "game": "Enter the Gungeon",
    "tags": [
      "weapon"
    ]
  }
];

if (typeof window !== 'undefined') window.CARDS_DATA = CARDS_DATA;
