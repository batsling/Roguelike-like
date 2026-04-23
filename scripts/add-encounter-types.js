#!/usr/bin/env node

// Script to add encounterType to all games in games-data.js
const fs = require('fs');
const path = require('path');

const filePath = path.join(__dirname, 'games-data.js');

// Read the file
console.log('Reading games-data.js...');
let content = fs.readFileSync(filePath, 'utf8');

// Count number of game objects
const gameCount = (content.match(/\{\s*"name":/g) || []).length;
console.log(`Found ${gameCount} games`);

// Function to determine encounter type
function getEncounterType() {
  const roll = Math.random() * 100;
  if (roll < 75) return 'combat';
  if (roll < 90) return 'event';
  return 'shop';
}

// Replace each game object to add encounterType after the coverImage property
let replacedCount = 0;
content = content.replace(/"coverImage":\s*"[^"]*"(\s*)(,)?(\s*\})/g, (match, whitespace1, comma, closingBrace) => {
  // Only add if encounterType doesn't already exist
  if (!match.includes('encounterType')) {
    replacedCount++;
    return match.replace(/(\s*)(,)?(\s*\})/, `,\n    "encounterType": "${getEncounterType()}"$3`);
  }
  return match;
});

console.log(`Added encounterType to ${replacedCount} games`);

// Write the file
fs.writeFileSync(filePath, content, 'utf8');

console.log('✓ Successfully updated games-data.js!');

// Count distribution
const combatCount = (content.match(/"encounterType":\s*"combat"/g) || []).length;
const eventCount = (content.match(/"encounterType":\s*"event"/g) || []).length;
const shopCount = (content.match(/"encounterType":\s*"shop"/g) || []).length;

console.log(`\nDistribution:`);
console.log(`  Combat: ${combatCount} (${(combatCount/gameCount*100).toFixed(1)}%)`);
console.log(`  Event: ${eventCount} (${(eventCount/gameCount*100).toFixed(1)}%)`);
console.log(`  Shop: ${shopCount} (${(shopCount/gameCount*100).toFixed(1)}%)`);
