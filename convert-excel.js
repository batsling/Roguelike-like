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
  const game = {
    name: name,
    year: parseInt(row['Year']) || 0,
    type: row['Type'] || 'Traditional',
    connected: row['Connected?'] === true || row['Connected?'] === 'TRUE',
    influenced: row['Influencer?'] === true || row['Influencer?'] === 'TRUE',
    tags: [],
    gamesInfluenced: [],
    coverImage: `images/covers/${name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')}.jpg`
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

// ============== CHARACTERS ==============
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

  characters[key] = {
    name: name,
    game: row['Game'] || '',
    icon: `images/characters/Icon/${name}.png`,
    fullImage: `images/characters/Full/${name}.png`,
    energy: parseInt(row['Energy']) || 2,
    mana: parseInt(row['Mana']) || 0,
    levelUpCondition: row['Level Up'] || '',
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
    combatStart: row['Combat Start'] || 'Dice',
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

  return {
    name: row['Name'] || '',
    type: row['Type'] || '',
    difficulty: row['Difficulty'] || 'Low',
    hp: parseInt(row['HP']) || 10,
    ability: row['Ability'] || null,
    game: row['Game'] || '',
    location: row['Location'] || 'General',
    dice: diceFaces,
    imageUrl: row['File'] ? `images/enemies/${row['File']}.png` : null
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
const weaponsSheet = workbook.Sheets['weapons'];
if (weaponsSheet) {
  const weaponsData = XLSX.utils.sheet_to_json(weaponsSheet);

  const weapons = weaponsData.map(row => {
    const diceFaces = [];
    for (let i = 1; i <= 6; i++) {
      const faceStr = row[`Dice Face ${i}`];
      diceFaces.push(parseDiceFace(faceStr));
    }

    return {
      name: row['Name'] || '',
      rarity: row['Rarity'] || 'Common',
      dice: diceFaces
    };
  });

  const weaponsOutput = `// Auto-generated from Roguelikes.xlsx - Weapons
// Weapons with combat dice

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

console.log('\n✅ All data files generated successfully!');
