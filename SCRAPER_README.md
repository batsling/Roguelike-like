# Steam Cover Scraper

Automatically fetch and download cover images for all games in your roguelike database from Steam.

## Features

✅ **Smart Caching** - API responses cached to `.cache/steam-cache.json` to avoid redundant requests
✅ **Rate Limiting** - 1.5 second delay between requests to respect Steam's servers
✅ **Retry Logic** - Automatic retries with exponential backoff for failed requests
✅ **Multiple Image Types** - Tries library cover, header, and capsule in order
✅ **Fallback System** - Uses placeholder image for games not found on Steam
✅ **Automatic Backup** - Creates `games-data.js.backup` before modifying
✅ **Progress Tracking** - Real-time console output showing progress and statistics

## Requirements

- Node.js (v14 or higher)
- Internet connection
- Write access to `games-data.js` and `images/covers/`

## Usage

### Run the scraper:

```bash
node scrape-covers.js
```

The script will:
1. Read all games from `games-data.js`
2. Search Steam for each game
3. Download cover images to `images/covers/`
4. Update `games-data.js` with `coverImage` property for each game
5. Use placeholder image for games not found on Steam

### Output Example:

```
🎮 Steam Cover Scraper Started

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📖 Reading games data...
✅ Found 450 games

[1/450] Processing: Slay the Spire
────────────────────────────────────────────────────────────
  📥 Downloading library_600x900 for "Slay the Spire"...
  ✅ Downloaded: slay-the-spire.jpg

[2/450] Processing: Hades
────────────────────────────────────────────────────────────
  💾 Using cached result for "Hades"
  ✅ Cover already exists: hades.jpg

...

📊 SCRAPING COMPLETE!

Total games:       450
✅ Found on Steam:  420
❌ Not found:       30
📥 Downloaded:      400
⚠️  Errors:          0

✨ All done! Cover images are in: ./images/covers
```

## Files Created/Modified

### Created:
- `images/covers/*.jpg` - Downloaded cover images
- `images/covers/no-cover.svg` - Placeholder for missing covers
- `.cache/steam-cache.json` - API response cache
- `games-data.js.backup` - Backup of original data

### Modified:
- `games-data.js` - Updated with `coverImage` property for each game

## Cache System

The scraper caches Steam search results in `.cache/steam-cache.json`:

```json
{
  "Slay the Spire": {
    "appId": 646570,
    "name": "Slay the Spire",
    "found": true
  },
  "Some Non-Steam Game": {
    "found": false
  }
}
```

### Benefits:
- **Fast re-runs** - Subsequent runs skip Steam API calls for cached games
- **Bandwidth savings** - No redundant API requests
- **Resume capability** - Stop and resume scraping without losing progress

### Clear cache:
```bash
rm .cache/steam-cache.json
```

## Configuration

Edit `scrape-covers.js` to customize:

```javascript
const RATE_LIMIT_DELAY = 1500;  // Delay between requests (ms)
const RETRY_ATTEMPTS = 3;        // Number of retry attempts
const RETRY_DELAY = 2000;        // Delay between retries (ms)
```

## Troubleshooting

### "Could not parse GAMES_DATA from file"
- Ensure `games-data.js` has proper format: `var GAMES_DATA = [...];`

### "HTTP 429" errors
- Steam is rate limiting. Increase `RATE_LIMIT_DELAY` to 2000-3000ms

### Missing covers after scraping
- Some games may not be on Steam
- Check `.cache/steam-cache.json` to see which games were not found
- Manually search for these games and add cover images to `images/covers/`
- Update `coverImage` property in `games-data.js` manually

### Network errors
- Check internet connection
- Steam servers may be temporarily unavailable
- Script will auto-retry up to 3 times

## Manual Cover Addition

For games not on Steam:

1. Find cover image elsewhere (itch.io, official website, etc.)
2. Save as `images/covers/game-name.jpg`
3. Update `games-data.js`:

```javascript
{
  "name": "Some Indie Game",
  "coverImage": "images/covers/some-indie-game.jpg",
  ...
}
```

## Image Specifications

Steam provides these image types (script tries in order):

1. **library_600x900.jpg** - Vertical cover (600x900) - Best for game cards
2. **header.jpg** - Header image (460x215) - Fallback
3. **capsule_616x353.jpg** - Capsule image (616x353) - Last resort

Placeholder image:
- **no-cover.svg** - Vector placeholder (600x900)

## Performance

Approximate time for different collection sizes:

- **100 games**: ~3-4 minutes (with cache: ~30 seconds)
- **500 games**: ~12-15 minutes (with cache: ~2 minutes)
- **1000 games**: ~25-30 minutes (with cache: ~4 minutes)

Rate limiting is intentional to be respectful to Steam's servers.

## Tips

- **Run overnight** for large collections
- **Check backup** before re-running
- **Review results** and manually add missing covers
- **Keep cache** for faster subsequent runs
- **Git commit** after successful scraping

## License

This scraper is for personal use. Steam cover images are property of their respective publishers.
