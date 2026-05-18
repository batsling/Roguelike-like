/**
 * ESM entry point for the data layer.
 *
 * Phase 5a (ESM migration): the 20 data files in data/* are real ES modules
 * with named exports (export { FOO_DATA }) AND a compat shim that writes
 * window.FOO_DATA so the still-classic JS files in js/* can read them
 * through the global scope they expect.
 *
 * This file is loaded as <script type="module"> from index.html in place of
 * the previous 20 individual <script> tags. Imports are side-effect only:
 * each imported module's top-level code runs (including the
 * `if (typeof window !== 'undefined') window.X = X` line), which exposes
 * the data globals just like before.
 *
 * The 18 files that index.html previously loaded keep their behavior;
 * fish-data.js and bingo-data.js are also pulled in here (collection.js
 * was referencing FISH_DATA without it being loaded — a latent
 * ReferenceError at runtime if the user opened the Fish collection tab).
 */

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
import '../data/fish-data.js';
import '../data/bingo-data.js';
