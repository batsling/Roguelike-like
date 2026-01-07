#!/usr/bin/env node
const XLSX = require('xlsx');
const fs = require('fs');

// Read the Excel file
const workbook = XLSX.readFile('Roguelikes.xlsx');

// Read games sheet
const gamesSheet = workbook.Sheets['games'];
const gamesData = XLSX.utils.sheet_to_json(gamesSheet);

// Read connections sheet
const connectionsSheet = workbook.Sheets['connections'];
const connectionsData = XLSX.utils.sheet_to_json(connectionsSheet);

// Create a map for game data
const gamesMap = new Map();

// Process games
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

  // Fix cover image for special cases
  if (game.coverImage === 'images/covers/-.jpg' || game.coverImage === 'images/covers/.jpg') {
    game.coverImage = 'images/covers/no-cover.svg';
  }

  gamesMap.set(name, game);
});

// Process connections
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

// Convert map to array
const games = Array.from(gamesMap.values());

// Sort by name
games.sort((a, b) => a.name.localeCompare(b.name));

// Count stats
const totalGames = games.length;
const totalConnections = connectionsData.length;
const connectedGames = games.filter(g => g.connected).length;
const influencers = games.filter(g => g.influenced).length;

// Generate the JavaScript file
const output = `// Auto-generated from Roguelikes.xlsx
// ${totalGames} games, ${totalConnections} connections
// ${connectedGames} connected, ${influencers} influencers

var GAMES_DATA = ${JSON.stringify(games, null, 2)};
`;

// Write to file
fs.writeFileSync('games-data.js', output);

console.log(`✅ Converted ${totalGames} games with ${totalConnections} connections`);
console.log(`   Connected games: ${connectedGames}`);
console.log(`   Influencers: ${influencers}`);
