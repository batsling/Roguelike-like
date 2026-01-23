# Game Data Files

This directory contains JSON files that define game content. You can edit these files to customize your roguelike experience!

## File Structure

### characters.json
Defines playable characters with starting stats.

```json
{
  "character_id": {
    "name": "Character Name",
    "icon": "url_to_icon_image",
    "startingStats": {
      "strength": 0,
      "dexterity": 2,
      "intelligence": 1,
      "charisma": 0
    },
    "description": "Character description"
  }
}
```

### items.json
Array of items players can find.

```json
[
  {
    "name": "Item Name",
    "rarity": "common|uncommon|rare",
    "type": "consumable|weapon|armor|trinket|artifact",
    "description": "What the item does"
  }
]
```

### enemies.json
Array of enemies for combat encounters.

```json
[
  {
    "name": "Enemy Name",
    "powerLevel": "1|2|3",
    "game": "Which roguelike they're from",
    "stat": "Strength|Dexterity|Intelligence|Charisma",
    "rollCheck": 10,
    "successReward": "What you get for winning",
    "failureConsequence": "What happens if you lose",
    "imageUrl": "url_to_enemy_image"
  }
]
```

### events.json
Array of story events with choices.

```json
[
  {
    "name": "Event Name",
    "description": "What's happening",
    "options": [
      "Choice 1",
      "Choice 2",
      "Choice 3",
      "Choice 4"
    ]
  }
]
```

### curses.json
Array of curses that can affect the player.

```json
[
  {
    "name": "Curse Name",
    "stat": "Strength|Dexterity|Intelligence|Charisma|All",
    "powerLevel": "1|2|3",
    "duration": "3 encounters|permanent",
    "description": "What the curse does"
  }
]
```

## Excel File Format

The game still supports loading from Excel files with this structure:

**Sheet 1: Games**
- Column A: Name
- Column B: Year
- Column C: Type (Action|Deckbuilder|Strategy|Traditional)
- Column D: Connected (TRUE/FALSE)
- Column E: Influenced (TRUE/FALSE)

**Sheet 2: Connections**
- Column A: Influencer (game name)
- Column B: Influencee (game name)

**Sheet 3: Items** (same structure as items.json)
**Sheet 4: Events** (same structure as events.json)
**Sheet 5: Enemies** (same structure as enemies.json)
**Sheet 6: Curses** (same structure as curses.json)

## Adding New Content

1. **Add a new character**: Edit `characters.json` and add a new entry
2. **Add new items**: Add objects to the `items.json` array
3. **Add new enemies**: Add objects to the `enemies.json` array
4. **Add new events**: Add objects to the `events.json` array
5. **Add new curses**: Add objects to the `curses.json` array

Make sure to follow the JSON format exactly - use commas between entries, but not after the last one!
