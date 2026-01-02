# 🚀 Quick Start: Steam Cover Scraper

Get game cover images from Steam in 3 easy steps!

## Step 1: Test the Scraper (30 seconds)

Run a quick test on the first 5 games to make sure everything works:

```bash
node test-scraper.js
```

**Expected output:**
```
✅ Successful: 4/5
❌ Failed:     1/5
```

This creates:
- `.cache/steam-cache.json` - Cached search results
- `images/covers/*.jpg` - Downloaded covers for test games

## Step 2: Run the Full Scraper (15-20 minutes)

If the test looks good, scrape all 525 games:

```bash
node scrape-covers.js
```

**What it does:**
- ✅ Searches Steam for each game
- ✅ Downloads cover images to `images/covers/`
- ✅ Updates `games-data.js` with `coverImage` property
- ✅ Creates backup at `games-data.js.backup`
- ✅ Uses placeholder for games not found on Steam

**Progress tracking:**
```
[450/525] Processing: Slay the Spire
────────────────────────────────────────────
  ✅ Found on Steam: Slay the Spire (App ID: 646570)
  📥 Downloading cover...
  ✅ Downloaded successfully
```

## Step 3: Review and Commit

**Check the results:**

```bash
ls -lh images/covers/    # See downloaded covers
cat .cache/steam-cache.json | grep '"found": false' | wc -l    # Count missing games
```

**Commit to git:**

```bash
git add games-data.js images/covers/ scrape-covers.js
git commit -m "Add Steam cover images for all games"
```

## That's it! 🎉

Your `games-data.js` now has cover images:

```javascript
{
  "name": "Slay the Spire",
  "year": 2019,
  "type": "Deckbuilding",
  "coverImage": "images/covers/slay-the-spire.jpg",  // ← New!
  ...
}
```

---

## Troubleshooting

### Games not found on Steam?

Some games may not be on Steam (itch.io exclusives, mobile games, etc.). The scraper uses a placeholder for these.

**To manually add covers:**

1. Download cover image
2. Save to `images/covers/game-name.jpg`
3. Edit `games-data.js`:
   ```javascript
   "coverImage": "images/covers/game-name.jpg"
   ```

### Want to re-run?

The scraper:
- ✅ Skips already downloaded covers
- ✅ Uses cached Steam search results
- ✅ Only downloads what's missing

Safe to run multiple times!

**Clear cache and start fresh:**
```bash
rm -rf .cache/ images/covers/*.jpg
node scrape-covers.js
```

---

## Next Steps

See **[SCRAPER_README.md](./SCRAPER_README.md)** for:
- Advanced configuration
- Detailed troubleshooting
- Cache management
- Performance tips

---

**Questions?** Check the [full documentation](./SCRAPER_README.md)
