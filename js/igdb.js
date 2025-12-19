// ===== IGDB.JS - IGDB API Integration for Game Covers =====
//
// This module handles:
// - IGDB API authentication
// - Game cover image fetching
// - Caching of results in localStorage
// - Fallback to text-only display

// ===== IGDB CONFIGURATION =====
// To use IGDB API, you need to:
// 1. Register at https://api-docs.igdb.com/#account-creation
// 2. Create a Twitch application at https://dev.twitch.tv/console/apps
// 3. Get your Client ID and Client Secret
// 4. Set them in the configuration below or via the UI

const IGDB_CONFIG = {
  clientId: '', // Set your Twitch Client ID here
  clientSecret: '', // Set your Twitch Client Secret here
  accessToken: null,
  tokenExpiry: null
};

// Cache for game cover URLs
const coverCache = {};

// ===== AUTHENTICATION =====

async function getIGDBAccessToken() {
  // Check if we have a valid cached token
  const cachedToken = localStorage.getItem('igdb_access_token');
  const cachedExpiry = localStorage.getItem('igdb_token_expiry');

  if (cachedToken && cachedExpiry && Date.now() < parseInt(cachedExpiry)) {
    IGDB_CONFIG.accessToken = cachedToken;
    return cachedToken;
  }

  // Check if credentials are set
  if (!IGDB_CONFIG.clientId || !IGDB_CONFIG.clientSecret) {
    console.warn('IGDB API credentials not configured. Game covers will not be loaded.');
    return null;
  }

  try {
    // Get OAuth token from Twitch
    const response = await fetch('https://id.twitch.tv/oauth2/token', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: `client_id=${IGDB_CONFIG.clientId}&client_secret=${IGDB_CONFIG.clientSecret}&grant_type=client_credentials`
    });

    if (!response.ok) {
      throw new Error(`Failed to get access token: ${response.status}`);
    }

    const data = await response.json();
    IGDB_CONFIG.accessToken = data.access_token;
    IGDB_CONFIG.tokenExpiry = Date.now() + (data.expires_in * 1000);

    // Cache token
    localStorage.setItem('igdb_access_token', data.access_token);
    localStorage.setItem('igdb_token_expiry', IGDB_CONFIG.tokenExpiry.toString());

    return data.access_token;
  } catch (error) {
    console.error('Error getting IGDB access token:', error);
    return null;
  }
}

// ===== GAME COVER FETCHING =====

async function fetchGameCover(gameName, gameYear = null) {
  // Check cache first
  const cacheKey = `${gameName}_${gameYear || 'any'}`;
  if (coverCache[cacheKey]) {
    return coverCache[cacheKey];
  }

  // Check localStorage cache
  const cachedCover = localStorage.getItem(`igdb_cover_${cacheKey}`);
  if (cachedCover) {
    coverCache[cacheKey] = cachedCover;
    return cachedCover;
  }

  // Get access token
  const token = await getIGDBAccessToken();
  if (!token) {
    return null;
  }

  try {
    // Search for the game
    const searchQuery = gameYear
      ? `search "${gameName}"; fields name,cover.url,first_release_date; where first_release_date >= ${Math.floor(new Date(gameYear, 0, 1).getTime() / 1000)} & first_release_date <= ${Math.floor(new Date(gameYear, 11, 31).getTime() / 1000)}; limit 1;`
      : `search "${gameName}"; fields name,cover.url; limit 1;`;

    const response = await fetch('https://api.igdb.com/v4/games', {
      method: 'POST',
      headers: {
        'Client-ID': IGDB_CONFIG.clientId,
        'Authorization': `Bearer ${token}`,
        'Accept': 'application/json',
      },
      body: searchQuery
    });

    if (!response.ok) {
      throw new Error(`IGDB API error: ${response.status}`);
    }

    const games = await response.json();

    if (games.length > 0 && games[0].cover && games[0].cover.url) {
      // Convert to high-res cover URL
      let coverUrl = games[0].cover.url;
      coverUrl = coverUrl.replace('t_thumb', 't_cover_big');
      coverUrl = 'https:' + coverUrl;

      // Cache the result
      coverCache[cacheKey] = coverUrl;
      localStorage.setItem(`igdb_cover_${cacheKey}`, coverUrl);

      return coverUrl;
    }

    return null;
  } catch (error) {
    console.error(`Error fetching cover for "${gameName}":`, error);
    return null;
  }
}

// ===== BATCH FETCHING =====

async function prefetchGameCovers(games) {
  if (!IGDB_CONFIG.clientId) {
    console.log('IGDB not configured. Skipping cover prefetch.');
    return;
  }

  console.log(`Prefetching covers for ${games.length} games...`);

  // Fetch in batches to avoid rate limiting
  const batchSize = 5;
  for (let i = 0; i < games.length; i += batchSize) {
    const batch = games.slice(i, i + batchSize);
    await Promise.all(
      batch.map(game => fetchGameCover(game.name, game.year))
    );

    // Small delay between batches
    if (i + batchSize < games.length) {
      await new Promise(resolve => setTimeout(resolve, 500));
    }
  }

  console.log('Cover prefetch complete!');
}

// ===== CONFIGURATION UI =====

function setIGDBCredentials(clientId, clientSecret) {
  IGDB_CONFIG.clientId = clientId;
  IGDB_CONFIG.clientSecret = clientSecret;

  // Clear old token
  localStorage.removeItem('igdb_access_token');
  localStorage.removeItem('igdb_token_expiry');

  // Save credentials to localStorage (note: not secure, just for convenience)
  localStorage.setItem('igdb_client_id', clientId);
  localStorage.setItem('igdb_client_secret', clientSecret);
}

function loadIGDBCredentials() {
  const clientId = localStorage.getItem('igdb_client_id');
  const clientSecret = localStorage.getItem('igdb_client_secret');

  if (clientId && clientSecret) {
    IGDB_CONFIG.clientId = clientId;
    IGDB_CONFIG.clientSecret = clientSecret;
  }
}

// ===== CACHE MANAGEMENT =====

function clearCoverCache() {
  // Clear memory cache
  Object.keys(coverCache).forEach(key => delete coverCache[key]);

  // Clear localStorage cache
  Object.keys(localStorage).forEach(key => {
    if (key.startsWith('igdb_cover_')) {
      localStorage.removeItem(key);
    }
  });

  console.log('Cover cache cleared!');
}

// Load credentials on module initialization
loadIGDBCredentials();

// Export to global scope
window.IGDB_CONFIG = IGDB_CONFIG;
window.getIGDBAccessToken = getIGDBAccessToken;
window.fetchGameCover = fetchGameCover;
window.prefetchGameCovers = prefetchGameCovers;
window.setIGDBCredentials = setIGDBCredentials;
window.loadIGDBCredentials = loadIGDBCredentials;
window.clearCoverCache = clearCoverCache;
