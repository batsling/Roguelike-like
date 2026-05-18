const SCROLLS_DATA = [
  {
    name: "Scroll of Teleportation",
    rarity: "Common",
    preference: "Neutral",
    file: "Teleportation",
    outcomes: {
      crit_good: "Teleport to a Random Space closer to the Amulet Game by up to 3 Spaces.",
      good:      "Teleport to a Random Space with the same distance from the Amulet Game.",
      bad:       "Teleport to a Random Space farther away from the Amulet Game by up to 3 Spaces.",
      crit_bad:  "Teleport to a completely Random Space."
    }
  },
  {
    name: "Scroll of Identify",
    rarity: "Common",
    preference: "Positive",
    file: "Identify",
    outcomes: {
      crit_good: "Identify all of your Scrolls.",
      good:      "Choose up to 3 Scrolls to Identify.",
      bad:       "Choose 1 Scroll to Identify.",
      crit_bad:  "Identify 1 Random Scroll."
    }
  },
  {
    name: "Scroll of Create Monster",
    rarity: "Common",
    preference: "Negative",
    file: null,
    outcomes: {
      crit_good: "Add a Random Enemy with 2 or less Weight to the next Combat.",
      good:      "Add a Random Enemy with 3 or less Weight to the next Combat.",
      bad:       "Add a Random Enemy with 5 or less Weight to the next Combat.",
      crit_bad:  "Add 2 Random Enemies with 5 or less Weight to the next Combat."
    }
  },
  {
    name: "Scroll of Vorpalize Weapon",
    rarity: "Rare",
    preference: "Positive",
    file: null,
    outcomes: {
      crit_good: "Choose 1 Weapon Attack Card you own. It Gains +5 Dmg and Vorpal.",
      good:      "Choose 1 Weapon Attack Card you own. It Gains Vorpal.",
      bad:       "A Random Weapon Attack Card you own Gains +5 Dmg and Vorpal.",
      crit_bad:  "A Random Weapon Attack Card you own Gains Vorpal."
    }
  },
  {
    name: "Scroll of Scare Monster",
    rarity: "Uncommon",
    preference: "Positive",
    file: null,
    outcomes: {
      crit_good: "Stun all Enemies at the start of the next Combat.",
      good:      "Choose up to 3 Enemies to Stun at the start of the next Combat.",
      bad:       "Choose 1 Enemy to Stun at the start of the next Combat.",
      crit_bad:  "Stun 1 Random Enemy at the start of the next Combat."
    }
  },
  {
    name: "Blank Scroll",
    rarity: "Uncommon",
    preference: "Neutral",
    file: null,
    outcomes: {
      crit_good: "Does nothing.",
      good:      "Does nothing.",
      bad:       "Does nothing.",
      crit_bad:  "Does nothing."
    }
  },
  {
    name: "Scroll of Enchant Weapon",
    rarity: "Common",
    preference: "Positive",
    file: "EnchantWeapon",
    outcomes: {
      crit_good: "Choose 1 Weapon Attack Card you own. It Gains +5 Dmg and Retain.",
      good:      "Choose 1 Weapon Attack Card you own. It Gains +5 Dmg.",
      bad:       "A Random Weapon Attack Card you own Gains +5 Dmg.",
      crit_bad:  "A Random Weapon Attack Card you own Gains +2 Dmg."
    }
  },
  {
    name: "Scroll of Sleep",
    rarity: "Uncommon",
    preference: "Negative",
    file: null,
    outcomes: {
      crit_good: "Fall asleep and Gain +10 Health. You are Ambushed in your next Combat.",
      good:      "Fall asleep. You are Ambushed in your next Combat.",
      bad:       "Fall asleep and get a nightmare. You Gain +1 Fear and are Ambushed in your next Combat.",
      crit_bad:  "Fall asleep and get a nightmare. You Gain +3 Fear and are Ambushed in your next Combat."
    }
  },
  {
    name: "Scroll of Aggravate Monsters",
    rarity: "Uncommon",
    preference: "Negative",
    file: null,
    outcomes: {
      crit_good: "All Enemies Gain +1 Power in your next Combat.",
      good:      "All Enemies Gain +2 Power in your next Combat.",
      bad:       "All Enemies Gain +3 Power in your next Combat.",
      crit_bad:  "All Enemies Gain +3 Power and +3 Defense in your next Combat."
    }
  },
  {
    name: "Scroll of Fire",
    rarity: "Uncommon",
    preference: "Negative",
    file: null,
    outcomes: {
      crit_good: "Take 10 Magic Dmg Fire. All Enemies Take 10 Magic Dmg Fire in your next Combat.",
      good:      "Take 10 Magic Dmg Fire. All Enemies Take 10 Magic Dmg Fire in your next Combat. Destroy 1 Random Item.",
      bad:       "Take 10 Magic Dmg Fire. All Enemies Take 10 Magic Dmg Fire in your next Combat. Destroy 1 Random Item and 1 Random Scroll.",
      crit_bad:  "Take 10 Magic Dmg Fire. All Enemies Take 10 Magic Dmg Fire in your next Combat. Destroy 1 Random Item, 1 Random Scroll, and 1 Random Potion."
    }
  },
  {
    name: "Scroll of Amnesia",
    rarity: "Uncommon",
    preference: "Negative",
    file: "Amnesia",
    outcomes: {
      crit_good: "Forget 1 Identified Scroll and 1 Potion.",
      good:      "Forget up to 2 Identified Scrolls and 2 Potions.",
      bad:       "Forget up to 3 Identified Scrolls and 3 Potions. Forget 1 Random Spell.",
      crit_bad:  "Forget all Identified Scrolls and Potions. Forget 2 Random Spells."
    }
  },
  {
    name: "Scroll of Create Food",
    rarity: "Uncommon",
    preference: "Positive",
    file: null,
    outcomes: {
      crit_good: "Choose 1 of 2 Random Uncommon or higher Food Items.",
      good:      "Choose 1 of 2 Random Food Items.",
      bad:       "Get 1 Random Food Item.",
      crit_bad:  "Get 1 Random Common Food Item."
    }
  }
];


export { SCROLLS_DATA };
if (typeof window !== 'undefined') window.SCROLLS_DATA = SCROLLS_DATA;
