# Gusher art drop

The Gusher **reuses the Pacer body walk cycle** (no separate body art needed) and
adds a non-directional **blood-gush geyser** layer drawn at the top of the body,
looping while alive. Drop the gush sheet here; tell me its frame count / grid.
I'll slice → rename to:

**gush layer (non-directional, loops)**
- `gusher_gush_spew_*.png`

Body comes from the shared Pacer walk cycle (the importer references it).
Mechanic: the Gusher **wanders** and fires blood projectiles in **random
directions** on a cooldown (`RandomShots` ability) — it does **not** leave creep.

Suggested raw filename to drop:
- `gusher_gush_sheet.png`
