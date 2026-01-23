#!/usr/bin/env node

/**
 * Steam Cover Image Scraper
 *
 * This script fetches cover images for all games in games-data.js from Steam,
 * downloads them locally, and updates the games data with cover image paths.
 *
 * Usage: node scrape-covers.js
 */

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');

// Configuration
const GAMES_DATA_FILE = './games-data.js';
const COVERS_DIR = './images/covers';
const CACHE_FILE = './.cache/steam-cache.json';
const PLACEHOLDER_IMAGE = 'images/covers/no-cover.svg';
const RATE_LIMIT_DELAY = 1500; // 1.5 seconds between requests to be nice to Steam
const RETRY_ATTEMPTS = 3;
const RETRY_DELAY = 2000;

// Steam API endpoints
const STEAM_SEARCH_API = 'https://store.steampowered.com/api/storesearch/';
const STEAM_CDN = 'https://cdn.cloudflare.steamstatic.com/steam/apps/';

// Load cache
let cache = {};
if (fs.existsSync(CACHE_FILE)) {
  try {
    cache = JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8'));
    console.log(`📦 Loaded cache with ${Object.keys(cache).length} entries`);
  } catch (err) {
    console.warn('⚠️  Failed to load cache, starting fresh');
  }
}

// Save cache
function saveCache() {
  try {
    fs.mkdirSync(path.dirname(CACHE_FILE), { recursive: true });
    fs.writeFileSync(CACHE_FILE, JSON.stringify(cache, null, 2));
  } catch (err) {
    console.error('❌ Failed to save cache:', err.message);
  }
}

// Utility: Delay function
function delay(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// Utility: Safe filename
function sanitizeFilename(name) {
  return name
    .replace(/[^a-z0-9]/gi, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .toLowerCase();
}

// Utility: HTTP GET with promise and retries
function httpGet(url, retries = RETRY_ATTEMPTS) {
  return new Promise((resolve, reject) => {
    const protocol = url.startsWith('https') ? https : http;

    protocol.get(url, (res) => {
      if (res.statusCode === 302 || res.statusCode === 301) {
        // Handle redirect
        return httpGet(res.headers.location, retries).then(resolve).catch(reject);
      }

      if (res.statusCode !== 200) {
        if (retries > 0 && res.statusCode >= 500) {
          console.log(`  ⏳ Server error, retrying... (${retries} attempts left)`);
          return delay(RETRY_DELAY).then(() => {
            httpGet(url, retries - 1).then(resolve).catch(reject);
          });
        }
        return reject(new Error(`HTTP ${res.statusCode}`));
      }

      resolve(res);
    }).on('error', (err) => {
      if (retries > 0) {
        console.log(`  ⏳ Network error, retrying... (${retries} attempts left)`);
        delay(RETRY_DELAY).then(() => {
          httpGet(url, retries - 1).then(resolve).catch(reject);
        });
      } else {
        reject(err);
      }
    });
  });
}

// Search Steam for a game
async function searchSteam(gameName) {
  // Check cache first
  if (cache[gameName]) {
    console.log(`  💾 Using cached result for "${gameName}"`);
    return cache[gameName];
  }

  const url = `${STEAM_SEARCH_API}?term=${encodeURIComponent(gameName)}&l=english&cc=US`;

  try {
    const res = await httpGet(url);

    let data = '';
    for await (const chunk of res) {
      data += chunk;
    }

    const json = JSON.parse(data);

    if (json.items && json.items.length > 0) {
      const firstResult = json.items[0];
      const result = {
        appId: firstResult.id,
        name: firstResult.name,
        found: true
      };

      // Cache the result
      cache[gameName] = result;
      saveCache();

      return result;
    }

    // Not found
    const result = { found: false };
    cache[gameName] = result;
    saveCache();

    return result;
  } catch (err) {
    console.error(`  ❌ Steam search failed: ${err.message}`);
    return { found: false, error: err.message };
  }
}

// Download image from URL to file
async function downloadImage(url, filepath) {
  try {
    const res = await httpGet(url);

    const fileStream = fs.createWriteStream(filepath);

    return new Promise((resolve, reject) => {
      res.pipe(fileStream);
      fileStream.on('finish', () => {
        fileStream.close();
        resolve(true);
      });
      fileStream.on('error', (err) => {
        fs.unlink(filepath, () => {}); // Delete partial file
        reject(err);
      });
    });
  } catch (err) {
    throw new Error(`Download failed: ${err.message}`);
  }
}

// Get cover image for a game
async function getGameCover(gameName) {
  const searchResult = await searchSteam(gameName);

  if (!searchResult.found) {
    return null;
  }

  const appId = searchResult.appId;
  const filename = `${sanitizeFilename(gameName)}.jpg`;
  const filepath = path.join(COVERS_DIR, filename);

  // Skip if already downloaded
  if (fs.existsSync(filepath)) {
    console.log(`  ✅ Cover already exists: ${filename}`);
    return `images/covers/${filename}`;
  }

  // Try different cover image types
  const imageTypes = [
    { url: `${STEAM_CDN}${appId}/library_600x900.jpg`, name: 'library_600x900' },
    { url: `${STEAM_CDN}${appId}/header.jpg`, name: 'header' },
    { url: `${STEAM_CDN}${appId}/capsule_616x353.jpg`, name: 'capsule' }
  ];

  for (const imageType of imageTypes) {
    try {
      console.log(`  📥 Downloading ${imageType.name} for "${gameName}"...`);
      await downloadImage(imageType.url, filepath);
      console.log(`  ✅ Downloaded: ${filename}`);
      return `images/covers/${filename}`;
    } catch (err) {
      console.log(`  ⚠️  ${imageType.name} not available, trying next...`);
    }
  }

  console.log(`  ❌ No cover images available for "${gameName}"`);
  return null;
}

// Read games data
function readGamesData() {
  const content = fs.readFileSync(GAMES_DATA_FILE, 'utf8');

  // Extract the array from the JS file
  const match = content.match(/var GAMES_DATA = (\[[\s\S]*?\]);/);
  if (!match) {
    throw new Error('Could not parse GAMES_DATA from file');
  }

  const gamesData = JSON.parse(match[1]);
  return { content, gamesData };
}

// Update games data file with cover images
function updateGamesData(gamesData) {
  const jsonString = JSON.stringify(gamesData, null, 2);
  const newContent = `var GAMES_DATA = ${jsonString};\n`;

  // Backup original file
  const backupFile = GAMES_DATA_FILE + '.backup';
  fs.copyFileSync(GAMES_DATA_FILE, backupFile);
  console.log(`\n💾 Created backup: ${backupFile}`);

  // Write updated file
  fs.writeFileSync(GAMES_DATA_FILE, newContent);
  console.log(`✅ Updated ${GAMES_DATA_FILE}`);
}

// Main scraper function
async function scrapeCovers() {
  console.log('🎮 Steam Cover Scraper Started\n');
  console.log('━'.repeat(60));

  // Ensure directories exist
  fs.mkdirSync(COVERS_DIR, { recursive: true });
  fs.mkdirSync(path.dirname(CACHE_FILE), { recursive: true });

  // Read games data
  console.log('\n📖 Reading games data...');
  const { content, gamesData } = readGamesData();
  console.log(`✅ Found ${gamesData.length} games\n`);

  // Statistics
  const stats = {
    total: gamesData.length,
    found: 0,
    notFound: 0,
    downloaded: 0,
    cached: 0,
    errors: 0
  };

  // Process each game
  for (let i = 0; i < gamesData.length; i++) {
    const game = gamesData[i];
    const progress = `[${i + 1}/${gamesData.length}]`;

    console.log(`\n${progress} Processing: ${game.name}`);
    console.log('─'.repeat(60));

    try {
      const coverPath = await getGameCover(game.name);

      if (coverPath) {
        game.coverImage = coverPath;
        stats.found++;
        stats.downloaded++;
      } else {
        game.coverImage = PLACEHOLDER_IMAGE;
        stats.notFound++;
      }

      // Rate limiting
      if (i < gamesData.length - 1) {
        await delay(RATE_LIMIT_DELAY);
      }
    } catch (err) {
      console.error(`  ❌ Error processing "${game.name}": ${err.message}`);
      game.coverImage = PLACEHOLDER_IMAGE;
      stats.errors++;
    }
  }

  // Update the games data file
  console.log('\n' + '━'.repeat(60));
  console.log('\n📝 Updating games-data.js...');
  updateGamesData(gamesData);

  // Print statistics
  console.log('\n' + '━'.repeat(60));
  console.log('\n📊 SCRAPING COMPLETE!\n');
  console.log(`Total games:       ${stats.total}`);
  console.log(`✅ Found on Steam:  ${stats.found}`);
  console.log(`❌ Not found:       ${stats.notFound}`);
  console.log(`📥 Downloaded:      ${stats.downloaded}`);
  console.log(`⚠️  Errors:          ${stats.errors}`);
  console.log('\n' + '━'.repeat(60));
  console.log('\n✨ All done! Cover images are in: ' + COVERS_DIR);
  console.log('💡 Tip: Review games with missing covers and manually add images if needed.\n');
}

// Run the scraper
scrapeCovers().catch(err => {
  console.error('\n💥 Fatal error:', err);
  process.exit(1);
});
