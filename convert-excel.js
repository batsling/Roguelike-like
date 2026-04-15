#!/usr/bin/env node
const XLSX = require('xlsx');
const fs = require('fs');

// Read the Excel file
const workbook = XLSX.readFile('Roguelikes.xlsx');

// Helper function to parse dice face strings like "2 Dmg", "3 Dmg, 3 Oiled", "Get 1 Dodge"
function parseDiceFace(faceStr) {
  if (!faceStr || faceStr === 'X' || faceStr === 'x') {
    return { isBlank: true, effects: [] };
  }

  const effects = [];
  // Split by comma to handle multiple effects like "3 Dmg, 3 Oiled"
  const parts = faceStr.split(',').map(p => p.trim());

  for (const part of parts) {
    const effect = parseSingleEffect(part);
    if (effect) {
      effects.push(effect);
    }
  }

  return { isBlank: false, effects, raw: faceStr };
}

// Parse a single effect like "2 Dmg" or "Get 1 Dodge" or "3 Dmg Cleave"
function parseSingleEffect(effectStr) {
  if (!effectStr) return null;

  const tokens = effectStr.trim().split(/\s+/);
  if (tokens.length === 0) return null;

  const effect = {
    raw: effectStr,
    value: null,
    move: null,
    addons: [],
    target: null
  };

  // Known moves
  const moves = ['Dmg', 'Block', 'Heal', 'Reroll', 'Mana', 'Pain', 'Spawn', 'Alter', 'Get', 'Inflict', 'Cleanse', 'Assassinate', 'Vitality'];
  // Known addons
  const addons = ['Cantrip', 'Ranged', 'Overload', 'Cleave', 'Wide', 'Engage', 'Exhert', 'Multiply', 'Finesse', 'Wealth'];

  let i = 0;

  // Check for leading move like "Get" or "Inflict" or "Spawn" or "Alter"
  if (['Get', 'Inflict', 'Spawn', 'Alter'].includes(tokens[0])) {
    effect.move = tokens[0];
    i = 1;
    // Next token might be a number
    if (i < tokens.length && !isNaN(parseInt(tokens[i]))) {
      effect.value = parseInt(tokens[i]);
      i++;
    }
    // Rest is the target/status
    if (i < tokens.length) {
      // Collect remaining tokens as target (e.g., "Dodge" or "Revola (Standing)")
      const remaining = tokens.slice(i);
      // Check for addons in remaining
      const targetParts = [];
      for (const tok of remaining) {
        if (addons.some(a => tok.startsWith(a))) {
          effect.addons.push(tok);
        } else {
          targetParts.push(tok);
        }
      }
      effect.target = targetParts.join(' ');
    }
    return effect;
  }

  // Standard format: [number] [move] [addons...]
  // First token might be a number
  if (!isNaN(parseInt(tokens[0]))) {
    effect.value = parseInt(tokens[0]);
    i = 1;
  }

  // Next should be the move
  if (i < tokens.length) {
    const potentialMove = tokens[i];
    if (moves.includes(potentialMove)) {
      effect.move = potentialMove;
      i++;
    } else {
      // Check if it's a special format like "5 x Turn number Dmg"
      // For now, store as raw
      effect.move = potentialMove;
      i++;
    }
  }

  // Remaining tokens are addons or modifiers
  while (i < tokens.length) {
    effect.addons.push(tokens[i]);
    i++;
  }

  return effect;
}

// ============== GAMES ==============
const gamesSheet = workbook.Sheets['games'];
const gamesData = XLSX.utils.sheet_to_json(gamesSheet);

const connectionsSheet = workbook.Sheets['connections'];
const connectionsData = XLSX.utils.sheet_to_json(connectionsSheet);

const gamesMap = new Map();

gamesData.forEach(row => {
  const name = row['Name'];
  const fileName = row['File'];

  // Use File column if available, otherwise generate from name
  // Check for .png first, fallback to .jpg
  let coverImage;
  const baseName = (fileName && fileName.toString().trim())
    ? fileName.toString().trim()
    : name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  if (fs.existsSync(`images/covers/${baseName}.png`)) {
    coverImage = `images/covers/${baseName}.png`;
  } else {
    coverImage = `images/covers/${baseName}.jpg`;
  }

  const game = {
    name: name,
    year: parseInt(row['Year']) || 0,
    type: row['Type'] || 'Traditional',
    connected: row['Connected?'] === true || row['Connected?'] === 'TRUE',
    influenced: row['Influencer?'] === true || row['Influencer?'] === 'TRUE',
    tags: [],
    gamesInfluenced: [],
    coverImage: coverImage
  };

  if (game.coverImage === 'images/covers/-.jpg' || game.coverImage === 'images/covers/.jpg') {
    game.coverImage = 'images/covers/no-cover.svg';
  }

  gamesMap.set(name, game);
});

connectionsData.forEach(row => {
  const influencer = row['Influencer'];
  const influencee = row['Influencee'];

  if (influencer && influencee) {
    const game = gamesMap.get(influencer);
    if (game) {
      if (!game.gamesInfluenced.includes(influencee)) {
        game.gamesInfluenced.push(influencee);
      }
    }
  }
});

const games = Array.from(gamesMap.values());
games.sort((a, b) => a.name.localeCompare(b.name));

const totalGames = games.length;
const totalConnections = connectionsData.length;
const connectedGames = games.filter(g => g.connected).length;
const influencers = games.filter(g => g.influenced).length;

const gamesOutput = `// Auto-generated from Roguelikes.xlsx
// ${totalGames} games, ${totalConnections} connections
// ${connectedGames} connected, ${influencers} influencers

var GAMES_DATA = ${JSON.stringify(games, null, 2)};
`;

fs.writeFileSync('games-data.js', gamesOutput);
console.log(`✅ Games: ${totalGames} games with ${totalConnections} connections`);

// Parse starting deck from "5 Attacks, 4 Defends, 1 Bash" format
function parseDeckColumn(deckStr) {
  if (!deckStr) return [];
  const entries = [];
  const parts = deckStr.split(',').map(s => s.trim());
  for (const part of parts) {
    const match = part.match(/^(\d+)\s+(.+)$/);
    if (match) {
      const count = parseInt(match[1]);
      // Strip trailing 's' for plurals (Attacks→Attack, Defends→Defend) but not proper names
      let cardName = match[2].trim();
      entries.push({ cardName, count });
    }
  }
  return entries;
}

// ============== CHARACTERS ==============

/**
 * Parse the Reward column into a structured object.
 * Examples:
 *   "50 Gold"                  → { type: 'gold', amount: 50 }
 *   "1 Small Chest"            → { type: 'item' }
 *   "1 Ironclad Card Reward"   → { type: 'card', tag: 'ironclad' }
 *   "1 Silent Card Reward"     → { type: 'card', tag: 'silent' }
 *   "1 Spell"                  → { type: 'spell' }
 *   "N/A" / empty              → { type: 'none' }
 */
function parseReward(rewardStr) {
  if (!rewardStr || rewardStr.toString().trim() === 'N/A' || rewardStr.toString().trim() === '') {
    return { type: 'none' };
  }

  const s = rewardStr.toString().trim();

  // "50 Gold"
  const goldMatch = s.match(/^(\d+)\s+Gold$/i);
  if (goldMatch) return { type: 'gold', amount: parseInt(goldMatch[1]) };

  // "1 Small Chest"
  if (/small\s+chest/i.test(s)) return { type: 'item' };

  // "1 Spell"
  if (/spell/i.test(s)) return { type: 'spell' };

  // "1 Ironclad Card Reward" / "1 Silent Card Reward" / etc.
  const cardMatch = s.match(/1\s+(\w+)\s+Card\s+Reward/i);
  if (cardMatch) return { type: 'card', tag: cardMatch[1].toLowerCase() };

  return { type: 'none' };
}

const charactersSheet = workbook.Sheets['characters'];
const charactersData = XLSX.utils.sheet_to_json(charactersSheet);

const characters = {};
charactersData.forEach(row => {
  const name = row['Name'];
  const key = name.toLowerCase();

  // Parse dice faces
  const diceFaces = [];
  for (let i = 1; i <= 6; i++) {
    const faceStr = row[`Dice Face ${i}`];
    diceFaces.push(parseDiceFace(faceStr));
  }

  // Build starting deck from Strikes + Defends + up to 2 unique cards
  const startingDeck = [];
  const strikeCount = parseInt(row['Strikes']);
  const defendCount = parseInt(row['Defends']);
  if (strikeCount > 0) startingDeck.push({ cardName: 'Strike', count: strikeCount });
  if (defendCount > 0) startingDeck.push({ cardName: 'Defend', count: defendCount });
  const unique1 = (row['Unique 1'] || '').toString().trim();
  const unique2 = (row['Unique 2'] || '').toString().trim();
  if (unique1 && unique1 !== 'N/A') startingDeck.push({ cardName: unique1, count: 1 });
  if (unique2 && unique2 !== 'N/A') startingDeck.push({ cardName: unique2, count: 1 });

  // Parse starting items ("N/A" or comma-separated names)
  const rawItems = (row['Starting items'] || '').toString().trim();
  const startingItems = (rawItems === '' || rawItems === 'N/A')
    ? []
    : rawItems.split(',').map(s => s.trim()).filter(Boolean);

  characters[key] = {
    name: name,
    game: row['Game'] || '',
    icon: `images/characters/Icon/${name}.png`,
    fullImage: `images/characters/Full/${name}.png`,
    energy: parseInt(row['Energy']) || 2,
    health: parseInt(row['Health']) || 80,
    levelUpCondition: row['Level Up'] || '',
    levelUpReward: parseReward(row['Reward']),
    levelUpStats: {
      strength: parseInt(row['Str']) || 0,
      dexterity: parseInt(row['Dex']) || 0,
      intelligence: parseInt(row['Int']) || 0,
      charisma: parseInt(row['Cha']) || 0,
      reroll: parseInt(row['Reroll']) || 0,
      dash: parseInt(row['Dash']) || 0,
      skip: parseInt(row['Skip']) || 0,
      discovery: parseInt(row['Discovery']) || 0,
      fov: parseInt(row['FoV']) || 0,
      luck: parseInt(row['Luck']) || 0,
      random: parseInt(row['Random']) || 0
    },
    description: row['Description'] || '',
    combatStyle: row['Combat Style'] || 'Cards',
    startingDeck: startingDeck,
    startingItems: startingItems,
    dice: diceFaces
  };
});

const charactersOutput = `// Auto-generated from Roguelikes.xlsx - Characters
// Characters with dice-based combat

var CHARACTERS_DATA = ${JSON.stringify(characters, null, 2)};
`;

fs.writeFileSync('characters-data.js', charactersOutput);
console.log(`✅ Characters: ${Object.keys(characters).length} characters`);

// ============== ENEMIES ==============
const enemiesSheet = workbook.Sheets['enemies'];
const enemiesData = XLSX.utils.sheet_to_json(enemiesSheet);

const enemies = enemiesData.map(row => {
  const diceFaces = [];
  for (let i = 1; i <= 6; i++) {
    const faceStr = row[`Dice Face ${i}`];
    diceFaces.push(parseDiceFace(faceStr));
  }

  // Get variant field - if it references another enemy, this is a variant of that enemy
  const variantOf = row['Variant'] && row['Variant'] !== 'N/A' ? row['Variant'] : null;

  // Parse HP range "30-34" into { min, max }
  const hpStr = String(row['HP'] || '10');
  let hpMin, hpMax;
  const hpMatch = hpStr.match(/^(\d+)-(\d+)$/);
  if (hpMatch) {
    hpMin = parseInt(hpMatch[1]);
    hpMax = parseInt(hpMatch[2]);
  } else {
    hpMin = hpMax = parseInt(hpStr) || 10;
  }

  // Parse weight - may be N/A for spawn-only enemies
  const rawWeight = row['Weight'];
  const weight = (rawWeight !== undefined && rawWeight !== 'N/A' && rawWeight !== '') ? parseInt(rawWeight) : null;

  // Parse difficulty - may be N/A for spawn-only enemies
  const difficulty = (row['Difficulty'] && row['Difficulty'] !== 'N/A') ? row['Difficulty'] : null;

  // Parse pattern - determines intent behavior
  const pattern = row['Pattern'] || null;

  return {
    name: row['Name'] || '',
    type: row['Type'] || '',
    difficulty: difficulty,
    weight: weight,
    hpMin: hpMin,
    hpMax: hpMax,
    ability: row['Ability'] || null,
    pattern: pattern,
    game: row['Game'] || '',
    location: row['Location'] || 'General',
    dice: diceFaces,
    imageUrl: row['File'] ? `images/enemies/${row['File']}.png` : null,
    variantOf: variantOf
  };
});

const enemiesOutput = `// Auto-generated from Roguelikes.xlsx - Enemies
// Enemies with dice-based combat

var ENEMIES_DATA = ${JSON.stringify(enemies, null, 2)};
`;

fs.writeFileSync('enemies-data.js', enemiesOutput);
console.log(`✅ Enemies: ${enemies.length} enemies`);

// ============== ALLIES ==============
const alliesSheet = workbook.Sheets['allies'];
if (alliesSheet) {
  const alliesData = XLSX.utils.sheet_to_json(alliesSheet);

  const allies = alliesData.map(row => {
    const diceFaces = [];
    for (let i = 1; i <= 6; i++) {
      const faceStr = row[`Dice Face ${i}`];
      diceFaces.push(parseDiceFace(faceStr));
    }

    return {
      name: row['Name'] || '',
      type: row['Type'] || '',
      rarity: row['Rarity'] || 'Low',
      hp: parseInt(row['HP']) || 5,
      ability: row['Ability'] || null,
      game: row['Game'] || '',
      dice: diceFaces,
      imageUrl: row['File'] ? `images/allies/${row['File']}.png` : null
    };
  });

  const alliesOutput = `// Auto-generated from Roguelikes.xlsx - Allies
// Allies that provide dice in combat

var ALLIES_DATA = ${JSON.stringify(allies, null, 2)};
`;

  fs.writeFileSync('allies-data.js', alliesOutput);
  console.log(`✅ Allies: ${allies.length} allies`);
}

// ============== WEAPONS ==============
// Weapons now give a card when acquired; weapon sheet stores passive upgrade effects
const weaponsSheet = workbook.Sheets['weapons'];
if (weaponsSheet) {
  const weaponsData = XLSX.utils.sheet_to_json(weaponsSheet);

  const weapons = weaponsData.map(row => {
    const tags = row['tags'] ? row['tags'].split(',').map(t => t.trim()) : [];

    return {
      name: row['Name'] || '',
      rarity: row['Rarity'] || 'Common',
      upgradeEffect: row['Upgrade'] || '',
      game: row['Reference'] || '',
      tags: tags,
      imageUrl: row['img'] ? `images/items/${row['img']}.png` : null,
      unlockCondition: row['Unlock Condition'] || null
    };
  });

  const weaponsOutput = `// Auto-generated from Roguelikes.xlsx - Weapons
// Weapons are items that add a card to the deck when acquired; upgrade effect is the passive scaling condition

var WEAPONS_DATA = ${JSON.stringify(weapons, null, 2)};
`;

  fs.writeFileSync('weapons-data.js', weaponsOutput);
  console.log(`✅ Weapons: ${weapons.length} weapons`);
}

// ============== ITEMS ==============
const itemsSheet = workbook.Sheets['items'];
const itemsData = XLSX.utils.sheet_to_json(itemsSheet);

const items = itemsData.map(row => {
  const tags = row['tags'] ? row['tags'].split(',').map(t => t.trim()) : [];

  return {
    name: row['Item'] || '',
    rarity: row['Rating'] || 'Common',  // UI expects 'rarity' not 'rating'
    type: row['Type'] || 'Passive',
    description: row['Description'] || '',
    game: row['Reference'] || '',  // UI expects 'game' not 'reference'
    tags: tags,
    image: row['File'] ? `images/items/${row['File']}.png` : null,  // UI expects 'image' not 'imageUrl'
    unlockCondition: row['Unlock Condition'] || null
  };
});

const itemsOutput = `// Auto-generated from Roguelikes.xlsx - Items

var ITEMS_DATA = ${JSON.stringify(items, null, 2)};
`;

fs.writeFileSync('items-data.js', itemsOutput);
console.log(`✅ Items: ${items.length} items`);

// ============== STATUSES ==============
const statusesSheet = workbook.Sheets['statuses'];
if (statusesSheet) {
  const statusesData = XLSX.utils.sheet_to_json(statusesSheet);

  const statuses = {};
  statusesData.forEach(row => {
    const name = row['Name'] || '';
    const key = name.toLowerCase().replace(/\s+/g, '_');

    statuses[key] = {
      name: name,
      description: row['Description'] || '',
      type: row['Type'] || 'Debuff',
      stackable: row['Stackable'] === 'Yes',
      maxStack: row['Max Stack'] === 'N/A' ? null : parseInt(row['Max Stack']) || null,
      decay: row['Decay'] || 'None',
      who: row['Who'] || 'All',
      preference: row['Preference'] || 'Neutral',
      imageUrl: row['File'] ? `images/statuses/${row['File']}.png` : null
    };
  });

  const statusesOutput = `// Auto-generated from Roguelikes.xlsx - Combat Statuses

var STATUSES_DATA = ${JSON.stringify(statuses, null, 2)};
`;

  fs.writeFileSync('statuses-data.js', statusesOutput);
  console.log(`✅ Statuses: ${Object.keys(statuses).length} statuses`);
}

// ============== MOVES ==============
const movesSheet = workbook.Sheets['moves'];
if (movesSheet) {
  const movesData = XLSX.utils.sheet_to_json(movesSheet);

  const moves = {};
  movesData.forEach(row => {
    const name = row['Name'] || '';
    const key = name.toLowerCase();

    moves[key] = {
      name: name,
      description: row['Description'] || '',
      preferredTarget: row['Preferred Target'] || 'Enemy',
      bonusStat: row['Bonus'] || 'No',
      imageUrl: row['File'] ? `images/moves/${row['File']}.png` : null
    };
  });

  const movesOutput = `// Auto-generated from Roguelikes.xlsx - Combat Moves

var MOVES_DATA = ${JSON.stringify(moves, null, 2)};
`;

  fs.writeFileSync('moves-data.js', movesOutput);
  console.log(`✅ Moves: ${Object.keys(moves).length} moves`);
}

// ============== ADDONS ==============
const addonsSheet = workbook.Sheets['addons'];
if (addonsSheet) {
  const addonsData = XLSX.utils.sheet_to_json(addonsSheet);

  const addons = {};
  addonsData.forEach(row => {
    const name = row['Name'] || '';
    const key = name.toLowerCase().replace(/[^a-z]/g, '');

    addons[key] = {
      name: name,
      description: row['Description'] || '',
      canBeAttachedTo: row['Can Be Attatched To'] || 'All'
    };
  });

  const addonsOutput = `// Auto-generated from Roguelikes.xlsx - Combat Addons

var ADDONS_DATA = ${JSON.stringify(addons, null, 2)};
`;

  fs.writeFileSync('addons-data.js', addonsOutput);
  console.log(`✅ Addons: ${Object.keys(addons).length} addons`);
}

// ============== SPELLS ==============
const spellsSheet = workbook.Sheets['spells'];
if (spellsSheet) {
  const spellsData = XLSX.utils.sheet_to_json(spellsSheet);

  const spells = spellsData.map(row => {
    const keywords = row['Keywords'] && row['Keywords'] !== 'N/A'
      ? row['Keywords'].split(',').map(k => k.trim())
      : [];

    return {
      name: row['Name'] || '',
      cost: parseInt(row['Cost']) || 1,
      rarity: row['Rarity'] || 'Common',
      description: row['Description'] || '',
      keywords: keywords,
      affectedByBonus: row['Bonus'] === 'Yes',
      effects: parseDiceFace(row['Description']).effects,
      imageUrl: row['File'] ? `images/Spells/${row['File']}.png` : null
    };
  });

  const spellsOutput = `// Auto-generated from Roguelikes.xlsx - Spells

var SPELLS_DATA = ${JSON.stringify(spells, null, 2)};
`;

  fs.writeFileSync('spells-data.js', spellsOutput);
  console.log(`✅ Spells: ${spells.length} spells`);
}

// ============== SPELL KEYWORDS ==============
const spellKeywordsSheet = workbook.Sheets['spellkeywords'];
if (spellKeywordsSheet) {
  const spellKeywordsData = XLSX.utils.sheet_to_json(spellKeywordsSheet);

  const spellKeywords = {};
  spellKeywordsData.forEach(row => {
    const name = row['Name'] || '';
    const key = name.toLowerCase();

    spellKeywords[key] = {
      name: name,
      description: row['Description'] || ''
    };
  });

  const spellKeywordsOutput = `// Auto-generated from Roguelikes.xlsx - Spell Keywords

var SPELL_KEYWORDS_DATA = ${JSON.stringify(spellKeywords, null, 2)};
`;

  fs.writeFileSync('spell-keywords-data.js', spellKeywordsOutput);
  console.log(`✅ Spell Keywords: ${Object.keys(spellKeywords).length} keywords`);
}

// ============== CURSES ==============
const cursesSheet = workbook.Sheets['curses'];
if (cursesSheet) {
  const cursesData = XLSX.utils.sheet_to_json(cursesSheet);

  const curses = cursesData.map(row => {
    return {
      name: row['Name'] || '',
      stat: row['Stat'] || '',
      power: row['Power'] || 'Low',
      duration: row['Duration'] || '',
      description: row['Description'] || '',
      automatic: row['Automatic'] || 'Manual'
    };
  });

  const cursesOutput = `// Auto-generated from Roguelikes.xlsx - Curses

var CURSES_DATA = ${JSON.stringify(curses, null, 2)};
`;

  fs.writeFileSync('curses-data.js', cursesOutput);
  console.log(`✅ Curses: ${curses.length} curses`);
}

// ============== GAME STATUSES ==============
const gameStatusesSheet = workbook.Sheets['gamestatuses'];
if (gameStatusesSheet) {
  const gameStatusesData = XLSX.utils.sheet_to_json(gameStatusesSheet);

  const gameStatuses = {};
  gameStatusesData.forEach(row => {
    const name = row['Name'] || '';
    const key = name.toLowerCase();

    gameStatuses[key] = {
      name: name,
      description: row['Description'] || '',
      type: row['Type'] || 'Neutral'
    };
  });

  const gameStatusesOutput = `// Auto-generated from Roguelikes.xlsx - Game Statuses
// Statuses that can be applied to game spaces

var GAME_STATUSES_DATA = ${JSON.stringify(gameStatuses, null, 2)};
`;

  fs.writeFileSync('game-statuses-data.js', gameStatusesOutput);
  console.log(`✅ Game Statuses: ${Object.keys(gameStatuses).length} game statuses`);
}

// ============== FISH ==============
const fishSheet = workbook.Sheets['fish'];
if (fishSheet) {
  const fishData = XLSX.utils.sheet_to_json(fishSheet);

  const fish = fishData.map(row => {
    return {
      name: row['Name'] || '',
      rarity: row['Rarity'] || 'Common',
      types: row['Types'] ? row['Types'].split(',').map(t => t.trim()) : [],
      game: row['Game'] || '',
      imageUrl: row['Image'] ? `images/fish/${row['Image']}.png` : null
    };
  });

  const fishOutput = `// Auto-generated from Roguelikes.xlsx - Fish

var FISH_DATA = ${JSON.stringify(fish, null, 2)};
`;

  fs.writeFileSync('fish-data.js', fishOutput);
  console.log(`✅ Fish: ${fish.length} fish`);
}

// ============== BINGO ==============
const bingoSheet = workbook.Sheets['bingo'];
if (bingoSheet) {
  const bingoData = XLSX.utils.sheet_to_json(bingoSheet);

  const bingoGoals = bingoData.map(row => {
    return {
      goal: row['Goal'] || '',
      difficulty: (row['Difficulty'] || 'Normal').toLowerCase()
    };
  });

  const bingoOutput = `// Auto-generated from Roguelikes.xlsx - Bingo Goals

var BINGO_GOALS_DATA = ${JSON.stringify(bingoGoals, null, 2)};
`;

  fs.writeFileSync('bingo-data.js', bingoOutput);
  console.log(`✅ Bingo: ${bingoGoals.length} goals`);
}

// ============== CARDS ==============
const cardsSheet = workbook.Sheets['cards'];
if (cardsSheet) {
  const cardsData = XLSX.utils.sheet_to_json(cardsSheet);

  const cards = cardsData.map(row => {
    const tags = row['Tags'] ? row['Tags'].split(',').map(t => t.trim()) : [];
    const upgradedCost = row['Upgraded Cost'];
    const isStatusCard = (row['Type'] || '').toLowerCase() === 'status';

    return {
      name: row['Name'] || '',
      rarity: row['Rarity'] || 'Common',
      cost: parseInt(row['Cost']) || 0,
      type: row['Type'] || 'Attack',
      description: row['Description'] || '',
      upgradedDescription: (!isStatusCard && row['Upgraded Description'] && row['Upgraded Description'] !== 'N/A')
        ? row['Upgraded Description'] : null,
      upgradedCost: (!isStatusCard && upgradedCost !== undefined && upgradedCost !== 'N/A')
        ? parseInt(upgradedCost) : null,
      canUpgrade: !isStatusCard && row['Rarity'] !== 'Starter' && row['Upgraded Description'] !== 'N/A',
      isStatusCard: isStatusCard,
      imageUrl: (row['Img'] && row['Img'] !== 'N/A') ? `images/cards/${row['Img']}.png` : null,
      game: (row['Game'] && row['Game'] !== 'N/A') ? row['Game'] : null,
      tags: tags
    };
  });

  const cardsOutput = `// Auto-generated from Roguelikes.xlsx - Cards
// Card deck system: players build a deck from this pool

var CARDS_DATA = ${JSON.stringify(cards, null, 2)};
`;

  fs.writeFileSync('cards-data.js', cardsOutput);
  console.log(`✅ Cards: ${cards.length} cards`);
}

console.log('\n✅ All data files generated successfully!');
