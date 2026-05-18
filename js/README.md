# JavaScript Module Architecture

This directory contains all 38 JavaScript modules for Roguelike-Like. The codebase totals ~42k lines and is organized so each module has a single clear responsibility.

## Quick stats

| | |
|---|---|
| Modules | 38 |
| Total lines | ~42,287 |
| `main.js` size | 1,214 lines (down from 10,089 before the Phase 3 decomposition) |
| Largest module | `combat-engine.js` (6,304 lines) |
| Test files | 4 (54 tests) in `/tests/` |

---

## Module map

### Core data & state

| File | Lines | Responsibility |
|------|-------|----------------|
| `constants.js` | 285 | Storage keys, hand-size limits, z-index constants, magic numbers |
| `storage.js` | 126 | `GameStorage` wrapper around `localStorage` (load / save / list slots) |
| `state-mutator.js` | 661 | Single entry point for all state mutations + pub/sub event bus |
| `data.js` | 373 | State variables (`gold`, `health`, `inventory`, …), JSON loading hooks, character data |
| `bfs-cache.js` | 136 | Cached BFS pathfinder over the influence graph |

### Combat

| File | Lines | Responsibility |
|------|-------|----------------|
| `combat-engine.js` | 6,304 | Card resolution, status effects, enemy AI, intent parsing, spawning, death triggers |
| `combat-ui.js` | 4,278 | Fan-arc hand, drag-to-play, pile overlay, targeting mode, HP-diff animations |
| `combat-flow.js` | 2,667 | Combat orchestration — pre-combat events, initialization, victory routing |
| `combat-state.js` | 608 | Per-combat state container (energy, piles, statuses) |
| `combat-effects.js` | 162 | Floating numbers, hit splashes, visual effect helpers |
| `combat.js` | 323 | Legacy D20 rolling + critical-failure helpers used by the event engine |
| `dice-system.js` | 327 | Dice mechanics — slot management, face resolution |
| `dice-renderer.js` | 717 | Dice card rendering for the deck and dice tray |
| `cards.js` | 676 | Deck management, card reward modal, shop card services, pigment helpers |

### Encounters, events & exploration

| File | Lines | Responsibility |
|------|-------|----------------|
| `events.js` | 1,065 | Pre-combat / special event entry points, event modal orchestration |
| `event-engine.js` | 1,263 | Two-roll D20 event resolver, outcome tiers, effect parsing |
| `exploration.js` | 1,041 | Map exploration logic (FoV, choice generation, discovery) |
| `gameplay.js` | 1,017 | Game progression, path node creation, encounter type determination |
| `loot.js` | 1,106 | Loot rolls, chest opening, item-choice modal |
| `scrolls-potions.js` | 1,322 | Scrolls and potions system (identification, color shuffling, target picker) |
| `items.js` | 2,508 | `ITEM_EFFECTS` registry — every item's onAcquire / onUse / triggered behavior |
| `shop.js` | 870 | Shop modal, reroll cost ladder, Charisma + Frugality price modifiers |

### UI shell, screens & modals

| File | Lines | Responsibility |
|------|-------|----------------|
| `ui.js` | 1,369 | DOM refresh — top bar, stats sidebar, inventory; subscribes to StateMutator events |
| `modals.js` | 184 | `createGameModal()` / `closeGameModal()` utilities used by every other modal |
| `run-modals.js` | 1,414 | Run-time top-bar modals — deck, dice tray, spells, notification history |
| `map.js` | 215 | SVG map viewport — pan, zoom, marker placement |
| `map-render.js` | 1,118 | Map layout + rendering — node positioning, arrows, location boxes |
| `character-select.js` | 332 | Character grid + detail panel on main menu |
| `character-start.js` | 504 | Start-game flow — phase 2 game selection, starting items, deck setup |
| `verification.js` | 1,314 | Manual / restriction curse verification modals, death screen |
| `curse-manager.js` | 674 | Curse storage, filtering, duration tracking, application helpers |
| `escape.js` | 662 | Escape phase — game selection, visualization, victory screen |
| `collection.js` | 2,828 | Collection viewer — Games / Items / Enemies / Curses / Spells tabs |
| `bingo.js` | 469 | 3x3 bingo grid, goal generation, reward queue |
| `allies.js` | 342 | Ally summoning, ally state, removal hooks |
| `locations.js` | 791 | Location modifiers (Hades, Risk of Rain 2, etc.) |
| `dev-tools.js` | 1,022 | Dev-tools panel + settings panel — fully isolated from gameplay modules |

### Orchestration

| File | Lines | Responsibility |
|------|-------|----------------|
| `main.js` | 1,214 | `DOMContentLoaded` init, save/load orchestration, top-bar wiring, a few cross-cutting helpers |

---

## Load order (from `index.html`)

Scripts are classic `<script>` tags loaded in dependency order. The order below matches `index.html`:

```
1. constants.js, storage.js              → primitives, no dependencies
2. state-mutator.js, curse-manager.js    → state plumbing
3. locations.js, data.js                 → data layer
4. loot.js, scrolls-potions.js, items.js → item / loot systems
5. ui.js                                 → DOM refresh + StateMutator subscriber
6. combat-effects.js, dice-system.js, dice-renderer.js,
   combat-state.js, combat-engine.js, combat-ui.js,
   combat.js, combat-flow.js             → combat stack
7. events.js, gameplay.js, bfs-cache.js, map.js → encounters + map
8. modals.js, shop.js, cards.js          → UI + deck/shop
9. character-select.js, verification.js  → screens
10. collection.js, escape.js, exploration.js, bingo.js → end-game / meta
11. dev-tools.js, map-render.js, character-start.js,
    allies.js, run-modals.js             → ancillary screens
12. main.js                              → orchestrator
13. event-engine.js                      → loaded last (used by events.js but with delayed entry)
```

If you add a new module, place its `<script>` tag just before `main.js` unless it has no dependencies on later modules.

---

## Key patterns

### 1. State mutation via StateMutator

All gameplay state changes should flow through `StateMutator`. It applies the change, then publishes an event on its internal bus:

```javascript
StateMutator.applyDelta('gold', 5);        // gold += 5; publishes 'gold-changed'
StateMutator.set('health', 10);            // health = 10; publishes 'health-changed'
StateMutator.restoreState({...});          // bulk restore on load; publishes everything
```

`ui.js` subscribes during init and refreshes only what changed:

```javascript
StateMutator.on('gold-changed', () => updateTopBar());
StateMutator.on('health-changed', () => updateHealthDisplay());
```

This removes the old pattern where every mutation site had to remember which UI updaters to call.

### 2. Global exports for cross-module calls

Each module attaches its public surface to `window` at the bottom of the file:

```javascript
window.showDeckModal = showDeckModal;
window.addCardToDeck = addCardToDeck;
```

Consumers guard their calls so a missing export logs nothing:

```javascript
if (typeof updateTopBar === 'function') updateTopBar();
```

This pattern keeps the project loadable from a `file://` URL (double-click `index.html`) instead of requiring a dev server.

### 3. Modal lifecycle

All modals use `modals.js`:

```javascript
createGameModal(`<div>...</div>`);   // mounts a single full-screen modal
closeGameModal();                    // fades it out and removes it
```

Don't write a one-off modal — use `createGameModal()` so the close behavior, z-index, and outside-click handler stay consistent.

### 4. Pure helpers in main.js

`main.js` exposes a few helpers used across modules:

- `getPowerValue(power, scale)` — convert `"Low"`/`"Medium"`/`"High"` curse power strings to numeric
- `getPlayerStat(statName)` — read a stat by name (`"Strength"` → `strength`)
- `updateCurseUI()` — refresh all three curse displays at once

---

## Test infrastructure

Tests live in `/tests/`:

| File | What it covers |
|------|----------------|
| `setup.js` | jsdom environment + script loader for tests that need the full game |
| `state-mutator.test.js` | StateMutator delta / set / event publishing |
| `data-integrity.test.js` | Card / enemy / item data files (required fields, no duplicates) |
| `combat-engine-helpers.test.js` | Pattern parsing, ability string parsing, effect resolution helpers |
| `esm-data-smoke.test.js` | Smoke test that data files load and expose their globals |

Run with:

```
npm install     # one-time
npm test
```

Add a test whenever you fix a bug worth pinning down. The suite is intentionally small — better to have ten meaningful tests than a hundred shallow ones.

---

## Adding a new module

1. Create the file in `js/` and write your code.
2. Export your public functions at the bottom: `window.functionName = functionName;`
3. Add a `<script>` tag in `index.html` just before `main.js`, respecting any dependencies.
4. Document it in the module-map table above.

Don't add an `import` / `export` declaration — modules are classic scripts, not ES modules. (See the v6.6 entry in the top-level README for why.)

---

## Where things live (cheat sheet)

| Need to change… | Look in |
|-----------------|---------|
| Combat card resolution | `combat-engine.js` |
| Combat rendering / drag-to-play | `combat-ui.js` |
| Pre/post-combat flow | `combat-flow.js` |
| Card / spell / shop services | `cards.js` |
| Item behavior | `items.js` |
| Pre-combat event outcome tiers | `event-engine.js` |
| Specific events (Wild Muncher, Colosseum…) | `events.js` |
| Map node placement & arrows | `map-render.js` |
| Map pan / zoom | `map.js` |
| Dice tray UI | `run-modals.js` |
| Dice face resolution | `dice-system.js` |
| Curse application & filtering | `curse-manager.js` |
| Curse verification modals | `verification.js` |
| Scrolls / potions identification | `scrolls-potions.js` |
| Loot rolls / chest UI | `loot.js` |
| Shop pricing | `shop.js` |
| Collection viewer | `collection.js` |
| Bingo goals & rewards | `bingo.js` |
| Save / load | `storage.js` (storage) + `main.js` (orchestration) |
| Dev tools panel | `dev-tools.js` |
| Top bar / stats sidebar refresh | `ui.js` |
| Any state mutation | `state-mutator.js` |

---

## Common issues

**`functionName is not defined`** — Check that the module exports `window.functionName = functionName` at the bottom and that its `<script>` tag in `index.html` loads *before* the caller's.

**State change doesn't trigger UI refresh** — You're probably bypassing `StateMutator` (e.g. `gold += 5` instead of `StateMutator.applyDelta('gold', 5)`). The pub/sub bus only fires when the mutation goes through the API.

**Modal closes the whole combat screen** — Use `createGameModal()` only for screens that should fully cover the game. For in-combat overlays (pile viewer, etc.) build a `position: fixed` div manually with `z-index: 20000`.

**Test fails with `X is not defined` in jsdom** — `tests/setup.js` may not be loading the module you need. Add a load line for the relevant `js/*.js` file.

---

For game feature documentation see the top-level [README.md](../README.md).
