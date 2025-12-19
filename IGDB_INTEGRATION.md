# 🎮 IGDB Integration - Game Cover Images

Your Roguelike-Like game now supports displaying **actual game cover images** from IGDB (Internet Game Database) instead of just game names!

## ✨ Features

- **Automatic Cover Fetching**: Game covers are automatically fetched from IGDB when displaying nodes
- **Smart Caching**: Covers are cached in localStorage to minimize API calls
- **Graceful Fallback**: If a cover isn't found or IGDB isn't configured, falls back to text-only display
- **Year-Aware Search**: Uses game release year (if available) to find the correct game
- **High-Res Images**: Fetches high-quality cover images optimized for display

## 🚀 Setup Instructions

### 1. Get IGDB API Credentials

IGDB uses Twitch for authentication. Here's how to get your credentials:

1. **Create a Twitch Account** (if you don't have one)
   - Go to https://www.twitch.tv/signup
   - Complete the registration

2. **Register an Application**
   - Go to https://dev.twitch.tv/console/apps
   - Click "Register Your Application"
   - Fill in:
     - **Name**: "My Roguelike-Like Game" (or any name)
     - **OAuth Redirect URLs**: `http://localhost`
     - **Category**: "Game Integration" or "Other"
   - Click "Create"

3. **Get Your Credentials**
   - After creating, click "Manage" on your application
   - Copy your **Client ID**
   - Click "New Secret" and copy the **Client Secret**

### 2. Configure in the Game

1. **Open the Game**
   - Open `index.html` in your browser

2. **Open IGDB Configuration**
   - Click the "🎮 Configure Game Covers (IGDB)" button

3. **Enter Credentials**
   - Paste your **Client ID**
   - Paste your **Client Secret**
   - Click "Save Credentials"

4. **Test Connection** (Optional)
   - Click "Test Connection" to verify your credentials work
   - You should see "✅ Connection successful!"

### 3. Start Playing!

- Your game will now automatically fetch and display cover images
- The first time a cover is fetched, it may take a moment
- After that, it's cached and loads instantly

## 🎨 How It Works

### Visual Changes

**Before:**
```
┌─────────────────┐
│  Binding of     │
│     Isaac       │
└─────────────────┘
```

**After:**
```
┌─────────────────┐
│ [Cover Image]   │
├─────────────────┤
│ Binding of Isaac│
└─────────────────┘
```

### Technical Details

1. **Game Node Creation**: When creating a game node, the system:
   - Looks up the game by name in your game data
   - Fetches the cover from IGDB using game name + year (if available)
   - Caches the result in localStorage

2. **Caching Strategy**:
   - **First fetch**: Calls IGDB API (~1-2 seconds)
   - **Subsequent loads**: Instant from localStorage
   - **Cache key**: `{game_name}_{year}` (e.g., "The Binding of Isaac_2011")

3. **Fallback Behavior**:
   - If IGDB credentials aren't configured: Shows text-only
   - If game isn't found on IGDB: Shows text-only
   - If API request fails: Shows text-only
   - No errors or disruption to gameplay!

## 🔧 Troubleshooting

### "Connection failed" Error

**Problem**: Can't connect to IGDB API

**Solutions**:
- Double-check your Client ID and Client Secret
- Make sure you created the Twitch application correctly
- Verify the OAuth Redirect URL is set to `http://localhost`
- Try generating a new Client Secret

### Covers Not Loading

**Problem**: Game nodes still show text-only

**Possible Causes**:
1. **IGDB not configured**: Click "Configure Game Covers" and enter credentials
2. **Game not in IGDB**: Some games (especially very old or obscure ones) might not be in IGDB
3. **Cache issue**: Click "Clear Cache" and try again
4. **Network issue**: Check your internet connection

### Wrong Game Cover

**Problem**: Cover shows the wrong game

**Solutions**:
- Make sure your Excel file has accurate release years for games
- IGDB searches by game name + year to find the right match
- Without year data, IGDB returns the first match (which might be a remaster or different game)
- Click "Clear Cache" after updating game years in your Excel file

### Rate Limiting

**Problem**: Some covers fail to load after many requests

**Solution**:
- IGDB has rate limits (about 4 requests per second)
- The integration includes automatic delays between requests
- If you hit the limit, wait a few minutes and try again

## 📊 Performance

### API Calls

- **Without caching**: 1 API call per unique game
- **With caching**: 0 API calls (uses localStorage)
- **Cache size**: ~100-200 bytes per cover URL

### Load Times

- **First load**: 1-2 seconds per game (API request)
- **Cached load**: Instant (<10ms)
- **Batch loading**: Automatically paced to avoid rate limits

## 🔒 Security & Privacy

### Your Credentials

- **Stored locally**: Client ID and Secret are stored in your browser's localStorage
- **Never sent elsewhere**: Only sent to IGDB/Twitch authentication servers
- **Not visible to others**: Only accessible from your browser
- **Can be cleared**: Use "Clear All Data" or browser settings to remove

### Important Notes

⚠️ **Client Secret Security**:
- Normally, Client Secrets should be kept server-side
- This is a client-side-only application, so we store it in localStorage
- For personal use, this is acceptable
- **DO NOT** share your localStorage data or publish your credentials publicly

## 🛠️ Advanced Usage

### Prefetch All Covers

Want to load all covers at once? Add this to your browser console:

```javascript
// After loading Excel file with game data
await prefetchGameCovers(games);
```

This will fetch covers for all games in batches, respecting rate limits.

### Clear Specific Game Cache

```javascript
// Clear cache for one game
localStorage.removeItem('igdb_cover_The Binding of Isaac_2011');
```

### Disable IGDB (Temporary)

```javascript
// Set empty credentials to disable
setIGDBCredentials('', '');
```

## 📝 API Reference

### Functions Available

**From `igdb.js`:**

- `fetchGameCover(name, year)` - Fetch a single game cover
- `prefetchGameCovers(games)` - Batch fetch all covers
- `setIGDBCredentials(clientId, clientSecret)` - Set API credentials
- `clearCoverCache()` - Clear all cached covers
- `getIGDBAccessToken()` - Get or refresh OAuth token

### Example Usage

```javascript
// Fetch a cover
const coverUrl = await fetchGameCover('Hades', 2020);
if (coverUrl) {
  console.log('Cover URL:', coverUrl);
}

// Batch fetch
await prefetchGameCovers([
  { name: 'Hades', year: 2020 },
  { name: 'Dead Cells', year: 2018 }
]);
```

## 🎓 Resources

- **IGDB Documentation**: https://api-docs.igdb.com/
- **Twitch Developer Console**: https://dev.twitch.tv/console/apps
- **Rate Limits**: https://api-docs.igdb.com/#rate-limits

## 🚧 Future Improvements

Potential enhancements for the IGDB integration:

1. **Better Error Messages**: Show specific reasons why covers fail to load
2. **Manual Cover Upload**: Allow users to upload custom covers
3. **Cover Preview**: Preview covers in the IGDB config panel
4. **Batch Actions**: Prefetch all covers with one button click
5. **Alternative Search**: Try alternate game names if first search fails

---

**Need Help?**

If you encounter issues:
1. Check the browser console for error messages
2. Try the "Test Connection" button
3. Clear cache and try again
4. Verify your Excel file has accurate game names and years
