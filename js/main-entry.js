/**
 * Phase 5 ESM entry point.
 *
 * Loads every data and JS file as a side-effect import in the same
 * order index.html previously loaded them via <script> tags. Each
 * file's top-level code still runs (sets `window.X = X` for every
 * top-level declaration that other files reference cross-module),
 * so the rest of the codebase keeps working through the global
 * scope it expects.
 *
 * Replaces the 57 individual <script src="..."> tags in index.html
 * with one <script type="module" src="js/main-entry.js">.
 *
 * Phase 5b/c will replace the bare `window.X = X` re-exports with
 * named ESM imports/exports, file by file, and eventually delete
 * the 484 defensive `typeof X === 'function'` checks once the
 * dependency graph is explicit.
 */

// ===== Data layer (20 files) =====
import '../data/characters-data.js';
import '../data/games-data.js';
import '../data/items-data.js';
import '../data/potions-data.js';
import '../data/scrolls-data.js';
import '../data/enemies-data.js';
import '../data/events-data.js';
import '../data/curses-data.js';
import '../data/allies-data.js';
import '../data/weapons-data.js';
import '../data/cards-data.js';
import '../data/dice-data.js';
import '../data/statuses-data.js';
import '../data/moves-data.js';
import '../data/addons-data.js';
import '../data/spells-data.js';
import '../data/spell-keywords-data.js';
import '../data/game-statuses-data.js';

// ===== Utility layer =====
import './constants.js';
import './storage.js';
import './state-mutator.js';
import './curse-manager.js';
import './locations.js';

// ===== Game logic =====
import './data.js';
import './loot.js';
import './scrolls-potions.js';
import './items.js';
import './ui.js';
import './combat-effects.js';
import './dice-system.js';
import './dice-renderer.js';
import './combat-state.js';
import './combat-engine.js';
import './combat-ui.js';
import './combat.js';
import './combat-flow.js';
import './events.js';
import './gameplay.js';
import './bfs-cache.js';
import './map.js';
import './modals.js';
import './shop.js';
import './cards.js';
import './character-select.js';
import './verification.js';
import './collection.js';
import './escape.js';
import './exploration.js';
import './bingo.js';
import './dev-tools.js';
import './map-render.js';
import './character-start.js';
import './allies.js';
import './run-modals.js';
import './main.js';
import './event-engine.js';
