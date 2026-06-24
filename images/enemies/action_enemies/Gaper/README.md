# Gaper art drop

Drop the **raw sheets** here (whole sheets are fine — the importer slices them).
Tell me each sheet's grid: columns × rows, which rows are which direction, and
which frames are the death/attack. I'll slice → trim → normalise → rename to:

**body layer (directional; `side` faces RIGHT, left mirrored at runtime)**
- `gaper_body_walk_down_*.png`
- `gaper_body_walk_up_*.png`
- `gaper_body_walk_side_*.png`
- `gaper_body_death_*.png`

**head layer (non-directional; never turns to face the player)**
- `gaper_head_idle_*.png`
- `gaper_head_attack_*.png`   (the 4-frame gape)

Suggested raw filenames to drop:
- `gaper_body_sheet.png`  (the pink body walk + death sheet)
- `gaper_head_sheet.png`  (the head frames)
