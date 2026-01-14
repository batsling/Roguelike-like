# Enemy Images

This folder contains local enemy images for combat encounters. Images should be in PNG format.

## Required Images

The following enemy images are needed. Filename format is lowercase with hyphens instead of spaces:

| Enemy Name | Filename | Game Source |
|------------|----------|-------------|
| Cultist | `cultist.png` | Slay the Spire |
| Snecko | `snecko.png` | Slay the Spire |
| Transient | `transient.png` | Slay the Spire |
| Hobgoblin | `hobgoblin.png` | Rogue |
| Troll | `troll.png` | Rogue |
| Dragon | `dragon.png` | Rogue |
| Mung | `mung.png` | Qud |
| Revola | `revola.png` | Qud |
| Skinning Homunculus | `skinning-homunculus.png` | Qud |
| Gaper | `gaper.png` | The Binding of Isaac |
| Double Vis | `double-vis.png` | The Binding of Isaac |
| Tainted Pooter | `tainted-pooter.png` | The Binding of Isaac |
| Stone Golem | `stone-golem.png` | Teleporter Event |

## Image Requirements

- **Format**: PNG (recommended) or JPG
- **Size**: Approximately 200x200 pixels (or larger, will be scaled down)
- **Style**: Pixel art or sprite-based images work best
- **Background**: Transparent or dark background preferred

## Previous imgur URLs

The previous imgur URLs for reference:
- Cultist: https://i.imgur.com/ajKKRcC.png
- Snecko: https://i.imgur.com/RK1NDba.png
- Transient: https://i.imgur.com/0cXmirR.png
- Hobgoblin: https://i.imgur.com/A2PsbKv.png
- Troll: https://i.imgur.com/UEmw7K9.png
- Dragon: https://i.imgur.com/qyX0nMf.png
- Mung: https://i.imgur.com/kfbSTv7.png
- Revola: https://i.imgur.com/Db74QnA.png
- Skinning Homunculus: https://i.imgur.com/0ZzNMlg.png
- Gaper: https://i.imgur.com/GHYsk65.png
- Double Vis: https://i.imgur.com/LLdb6OR.png
- Tainted Pooter: https://i.imgur.com/IsLNEDt.png
- Stone Golem: https://imgur.com/AeB1zxt.png

## How It Works

The `getEnemyImagePath()` function in `js/data.js` automatically converts enemy names to filenames:
- Converts to lowercase
- Replaces non-alphanumeric characters with hyphens
- Adds `.png` extension

Example: "Stone Golem" → "stone-golem.png"

If an image file is missing, the image element will be hidden automatically using the `onerror` handler.
