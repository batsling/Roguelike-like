#!/usr/bin/env node

/**
 * Steam Cover Scraper - TEST VERSION
 *
 * This is a test version that only processes the first 5 games
 * to verify the scraper works before running on all 525+ games.
 *
 * Usage: node test-scraper.js
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
const RATE_LIMIT_DELAY = 1000; // Faster for testing
const TEST_LIMIT = 5; // Only process first 5 games

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

// Utility: HTTP GET with promise
function httpGet(url) {
  return new Promise((resolve, reject) => {
    const protocol = url.startsWith('https') ? https : http;

    protocol.get(url, (res) => {
      if (res.statusCode === 302 || res.statusCode === 301) {
        return httpGet(res.headers.location).then(resolve).catch(reject);
      }

      if (res.statusCode !== 200) {
        return reject(new Error(`HTTP ${res.statusCode}`));
      }

      resolve(res);
    }).on('error', reject);
  });
}

// Search Steam for a game
async function searchSteam(gameName) {
  if (cache[gameName]) {
    console.log(`  💾 Using cached result`);
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

      cache[gameName] = result;
      saveCache();
      return result;
    }

    const result = { found: false };
    cache[gameName] = result;
    saveCache();
    return result;
  } catch (err) {
    console.error(`  ❌ Steam search failed: ${err.message}`);
    return { found: false, error: err.message };
  }
}

// Download image
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
        fs.unlink(filepath, () => {});
        reject(err);
      });
    });
  } catch (err) {
    throw new Error(`Download failed: ${err.message}`);
  }
}

// Get cover image
async function getGameCover(gameName) {
  const searchResult = await searchSteam(gameName);

  if (!searchResult.found) {
    console.log(`  ❌ Not found on Steam`);
    return null;
  }

  console.log(`  ✅ Found on Steam: ${searchResult.name} (App ID: ${searchResult.appId})`);

  const appId = searchResult.appId;
  const filename = `${sanitizeFilename(gameName)}.jpg`;
  const filepath = path.join(COVERS_DIR, filename);

  if (fs.existsSync(filepath)) {
    console.log(`  ✅ Cover already exists`);
    return `images/covers/${filename}`;
  }

  const coverUrl = `${STEAM_CDN}${appId}/library_600x900.jpg`;

  try {
    console.log(`  📥 Downloading cover...`);
    await downloadImage(coverUrl, filepath);
    console.log(`  ✅ Downloaded successfully`);
    return `images/covers/${filename}`;
  } catch (err) {
    console.log(`  ⚠️  Cover download failed`);
    return null;
  }
}

// Main test function
async function testScraper() {
  console.log('🧪 Testing Steam Cover Scraper (First 5 Games)\n');
  console.log('━'.repeat(60));

  fs.mkdirSync(COVERS_DIR, { recursive: true });

  // Read games data
  const content = fs.readFileSync(GAMES_DATA_FILE, 'utf8');
  const match = content.match(/var GAMES_DATA = (\[[\s\S]*?\]);/);
  if (!match) {
    throw new Error('Could not parse GAMES_DATA');
  }

  const gamesData = JSON.parse(match[1]);
  const testGames = gamesData.slice(0, TEST_LIMIT);

  console.log(`\n📖 Testing with ${testGames.length} games:\n`);

  const results = [];

  for (let i = 0; i < testGames.length; i++) {
    const game = testGames[i];
    console.log(`[${i + 1}/${testGames.length}] ${game.name}`);
    console.log('─'.repeat(60));

    try {
      const coverPath = await getGameCover(game.name);
      results.push({
        name: game.name,
        success: !!coverPath,
        coverPath: coverPath || PLACEHOLDER_IMAGE
      });

      if (i < testGames.length - 1) {
        await delay(RATE_LIMIT_DELAY);
      }
    } catch (err) {
      console.error(`  ❌ Error: ${err.message}`);
      results.push({
        name: game.name,
        success: false,
        coverPath: PLACEHOLDER_IMAGE,
        error: err.message
      });
    }

    console.log('');
  }

  // Summary
  console.log('━'.repeat(60));
  console.log('\n📊 TEST RESULTS:\n');

  const successful = results.filter(r => r.success).length;
  const failed = results.filter(r => !r.success).length;

  console.log(`✅ Successful: ${successful}/${testGames.length}`);
  console.log(`❌ Failed:     ${failed}/${testGames.length}\n`);

  console.log('Results:');
  results.forEach((r, i) => {
    const status = r.success ? '✅' : '❌';
    console.log(`  ${status} ${r.name}`);
    if (r.coverPath !== PLACEHOLDER_IMAGE) {
      console.log(`      → ${r.coverPath}`);
    }
  });

  console.log('\n' + '━'.repeat(60));
  console.log('\n✨ Test complete!');
  console.log('\nIf results look good, run the full scraper:');
  console.log('  node scrape-covers.js\n');
}

testScraper().catch(err => {
  console.error('\n💥 Test failed:', err);
  process.exit(1);
});
