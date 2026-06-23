# Gusher art drop

The Gusher **reuses the Pacer body walk cycle** (no separate body art needed) and
adds a non-directional **blood-gush geyser** layer drawn at the top of the body,
looping while alive. Drop the gush sheet here; tell me its frame count / grid.
I'll slice → rename to:

**gush layer (non-directional, loops)**
- `gusher_gush_spew_*.png`

Body comes from the shared Pacer walk cycle (the importer references it).
The damaging floor creep uses the puddle sheet in `../_shared/` (see that folder).

Suggested raw filename to drop:
- `gusher_gush_sheet.png`
