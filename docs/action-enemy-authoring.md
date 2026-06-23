# Action Enemy Authoring (`enemiesA`)

Action-mode enemies are authored in the **`enemiesA`** sheet of
`tools/Roguelikes.xlsx` and compiled into `data/action_enemies/<id>.tres`
(`ActionEnemyData`). They are real-time creatures — positions, projectiles and
frame animations — so they use a different schema from the deckbuilder
`enemiesD` sheet.

## Pipeline

```
enemiesA sheet ──build_enemiesA_sheet.py──▶ (sheet)
              ──generate_action_enemy_tres.py──▶ data/action_enemies/<id>.tres
                                              └▶ assets/enemies/<id>/<anim>_<n>.png
```

1. `tools/build_enemiesA_sheet.py` (re)writes the `enemiesA` sheet from the
   `ENEMIES` list in that script — edit there, then run it.
2. `tools/generate_action_enemy_tres.py` reads the sheet, slices/normalises the
   art, and writes the `.tres` + per-frame PNGs. Re-run safe; it never touches
   the hand-authored `walker`/`shooter` placeholders (`PRESERVE`).

Both need `openpyxl` + `Pillow`.

## Columns

| Column | Notes |
|---|---|
| Name / Id | Display name / `StringName` id and asset-folder name. |
| Difficulty | `Low/Medium/High/Boss` → `0..3`. |
| Weight | Spawn weight. **Note:** action spawning currently picks uniformly by count (`ActionFloor._pick_enemies`); weight is forward-looking metadata until a budget spawner is ported to action. |
| Game / Tag | Source attribution / free tag. |
| Min/Max HP | HP rolled in range at spawn. |
| Contact Damage | Damage per touch (walker) or per projectile (shooter/stationary). |
| Attack Cooldown | Seconds between attacks. |
| Attack Range | Melee radius, or the distance at which a shooter/stationary enemy opens fire. |
| Preferred Distance | SHOOTER kiting distance (0 = `0.7 × Attack Range`). |
| Projectile Speed | px/s (0 = engine default). |
| Projectile Lifetime | Seconds before a shot expires (0 = engine default `3.0`). A deliberately *slow* shot that must still cross the arena needs `lifetime × speed ≥ ~980`. |
| Move Speed | px/s (0 = immobile). |
| Size | **Player-relative**: `1` = the player's starting size (`PLAYER_RADIUS`, 18px). The importer multiplies to pixels. |
| Behavior | `Walker / Shooter / Stationary`. |
| Color | `r,g,b[,a]` — only used as the fallback circle color when an enemy has no art. |
| Directional | `Yes/No` — reserved for facing-prefixed frames (walkers/gapers); non-directional enemies use plain frames. |
| Animations | Packed; see below. |
| Split Into / Split Count | Split status: spawn N copies of `<id>` at ≤50% HP. |

## `Animations` grammar

`;`-separated, each: `<name> @ <fps> <loop|once> [grid WxH]`

- **name** — `idle`, `attack`, `walk`, `death`, `attack2`, … The engine plays
  `attack` when an enemy fires and falls back to `idle` when a `once` animation
  finishes; `idle` should always be present.
- **fps / loop|once** — playback speed and whether it loops.
- **grid WxH** — if present, the source PNG is one sheet sliced into `WxH` cells
  (left-to-right, top-to-bottom); omit it when the PNG is a single frame.

Example (Horf): `idle @ 4 loop ; attack @ 8 once grid 32x32`

## Source art

Per enemy: `images/enemies/action_enemies/<Name>/<id>_<anim>*.png`
(e.g. `horf_idle.png`, `horf_attack_1.png`). Each animation's frames are found
by the `<id>_<anim>` prefix. The importer **trims every frame to its opaque
bounds and re-centres all of the enemy's frames on one shared square canvas**,
so animations share a consistent scale and the sprite never pops size when it
switches. Frames are drawn at `Size × 1.3` radius, mirroring the player token.

> Filtering: Godot 4 sets nearest/linear per-CanvasItem, not per-texture.
> Enemy sprites currently use the engine default (like the player avatar);
> a dedicated nearest-filter canvas layer is the clean follow-up if crisp
> upscaled pixels are wanted.
