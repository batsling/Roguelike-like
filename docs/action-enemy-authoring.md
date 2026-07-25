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
| Weight | Spend **cost** for the weighted room budget (`ActionEnemySpawner`). A Horf costs 2, so the Low-tier budget of 8 fields up to four. See "Spawning" below. |
| Game / Tag | Source attribution / free tag. |
| Min/Max HP | HP rolled in range at spawn. |
| Contact Damage | Damage per touch (walker) or per projectile (shooter/stationary). |
| Attack Cooldown | Seconds between attacks. |
| Attack Windup | Telegraph lead-time: a ranged enemy plays its `attack` animation for this many seconds as a warning *before* the projectile is released (the shot lands as the wind-up ends). `0` = use the attack animation's own length. Tune this to speed up / slow down the tell. |
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

## Spawning (weighted budget)

Each **room** is one encounter, built by `ActionEnemySpawner.build_room` (which
reuses the deckbuilder weighted pick loop, `EnemySpawner.pick_group`):

- The run's difficulty tier (`RunDifficulty.current_tier`) sets a per-room spend
  **budget**: Low **8** / Medium **10** / High **12** / Insane **15**.
- Each enemy's `Weight` is its **cost**. Enemies are picked until the budget or
  the room cap (`MAX_ENEMIES`, 8) runs out — so budget 8 + Horf (weight 2) = up
  to four Horfs.
- The candidate pool is gated to `difficulty ≤ tier` (Low tier → Low enemies
  only); `Boss` difficulty is reserved and never rolls into a random room.
- **Boss rooms** field a single registered `Boss`-difficulty enemy (see below);
  when none are authored they fall back to a `BOSS_BUDGET_MULT` (1.5×) budget of
  ordinary enemies. Either way boss rooms get an HP bump (`ActionFloor.BOSS_HP_MULT`).

Tune the budgets in `scripts/runtime/ActionEnemySpawner.gd` (`TIER_BUDGET`).

## Bosses

Mark an enemy `Difficulty` **Boss** and it's kept out of normal rooms and drawn
into **boss rooms** instead — `ActionEnemySpawner.build_boss_room` weighted-picks
one boss (by `Weight`) and places it solo. Register as many as you like; each
boss room fields one.

A boss usually wants the **boss brain** (`boss_brain = true`): instead of every
attack firing the instant it's off cooldown, the boss picks ONE ready, in-range
attack at a time — weighted by that attack's `weight` — then holds for
`attack_recovery` seconds before choosing again. That's what makes a kit of
hop / vomit / big-jump read as a one-move-at-a-time fight. Give each attack a
`weight` to bias the mix (a heavier vomit `weight` = vomits more than it jumps).

### Leap (jump) attacks — `AttackKind.LEAP`

A `LEAP` attack is a jump that goes airborne and slams down on the player
(Monstro's big jump; any slam boss). It runs in three beats — **crouch**
(telegraphed, still grounded and hittable) → **airborne** (untargetable,
non-solid, arcing to the player's position at take-off) → **land** (contact
damage inside `leap_land_radius` + an outward burst of `leap_burst_count`
tears). A ground shadow tracks the leaper to its landing spot and a red ring
telegraphs the impact zone while it's in the air.

The `LEAP` attack entry supplies the landing **damage / cooldown / trigger
range** like any attack; the arc/timing/burst live in enemy-level `leap_*`
fields (`leap_telegraph`, `leap_air_time`, `leap_height`, `leap_land_radius`,
`leap_burst_count`, `leap_burst_speed`, `leap_burst_lifetime`). Any left `0`
use `ActionCombat`'s `LEAP_DEFAULT_*` placeholders, so a leap can be authored
with just the attack entry and tuned later without touching code.

**Lobbed attacks (`attack_lob`).** A ranged attack flagged `lob` fires a
scattered burst of **arcing tears** instead of flat bolts — each lobs to a random
point around the enemy (`LOB_*` constants in `ActionCombat`), rising and falling
with a ground shadow, and only threatens the player when it's low to the ground
(you dodge where they land, not while they're overhead). On a `LEAP` attack the
same flag makes the landing tear-burst lob too. Monstro's vomit and big-jump
barrage both use it; ordinary shooters (Horf/Spitter) leave it off and keep their
flat aimed bolts.

**Multiple leaps per enemy.** The `attack_leap_*` arrays (parallel to the other
`attack_*` arrays) override the enemy-level defaults per attack, so one enemy can
own several different leaps. Monstro uses this for a tall slam **and** a short
hop: the slam inherits the enemy-level profile (tall, 12-tear burst), while the
hop entry sets a low `attack_leap_height`, short `attack_leap_telegraph`/
`attack_leap_air_time`, and `attack_leap_burst_counts = 0` (no tears). A float
override of `0` inherits the enemy default; for `attack_leap_burst_counts`, `-1`
inherits and `0` is an explicit "no burst". The grounded splat scales with the
leap's air time (`LEAP_LAND_TIME_FRAC`), so hops splat briefly and slams linger.

**Leap animations.** A leaper plays a clip per beat: crouch → airborne → land.
The clip names default to `jump` / `airborne` / `land` but each attack can name
its own via `attack_leap_crouch_anim` / `attack_leap_air_anim` /
`attack_leap_land_anim`, so one enemy's hop and big jump can use different frames.
Missing clips fall back to `attack`/`idle`, so a leaper animates even with only an
`attack` clip. A clip may be multi-frame (e.g. Monstro's hop land is `#6 → #9`,
splat then recover). Monstro's wiring: shared crouch `jump` (`#6 → #7`), hop air
`hopair` (`#8`) + land `hopland` (`#6 → #9`); big-jump air `descend` (`#5`) +
land `splat` (`#6`).

**Off-screen leaps (`attack_offscreen`).** A leap flagged off-screen vanishes for
the airborne beat and only drops back into view for the final descent
(`LEAP_DESCEND_*` in `ActionCombat`) — its shadow + landing ring still telegraph
where it will slam. Monstro's big jump uses this; the hop stays on screen. The engine also lifts the sprite by the arc
height and draws a ground shadow + a red landing-zone ring automatically, so
those don't need art. Author the leap clips alongside `idle`/`attack` in the
`Animations` column.

On top of the frames the engine adds **procedural squash-and-stretch** (anchored
at the feet, like the walk bob): an anticipation dip during the crouch, a stretch
through the air (strongest at take-off and just before landing), and a hard
flatten on impact that springs back with a small overshoot bounce — tuned by the
`LEAP_*_SQUASH`/`STRETCH` constants in `ActionCombat`. The land beat holds for
`max(land clip length, LEAP_DEFAULT_LAND_TIME)` so the flatten-and-spring reads,
showing the `land` frame for the first half of the beat and the round `idle`
frame for the spring (so the bounce deforms a round shape, not the flat pancake).

`data/action_enemies/monstro.tres` is the first boss — Basement's Monstro (boss
brain + a big jump and a vomit volley), authored from Rebirth's behaviour. It
renders as a fleshy circle until its sprite frames (`monstro_idle`,
`monstro_jump`, `monstro_airborne`, `monstro_land`, `monstro_attack`) are dropped
into `images/enemies/action_enemies/Monstro/` and compiled.

Enemies don't appear instantly: each spawn is **telegraphed** by a red circle
(sized to the enemy) for `ActionCombat.SPAWN_TELEGRAPH_TIME` (1s) before the
enemy materialises, so the player can read the room first. A room mid-telegraph
never counts as cleared.

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
