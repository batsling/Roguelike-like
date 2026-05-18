/**
 * Test harness.
 *
 * Phase 5a (partial ESM migration): the data layer is now real ES
 * modules. We import them via static `import` (each module's compat
 * shim writes window.X, so globalThis.X is set after import).
 *
 * The js/* files are still classic <script> bodies that use `var` at
 * file scope and assume `globalThis === window`. To run them under
 * Vitest+jsdom we read each file and indirect-eval it in global scope,
 * which mirrors what a <script> tag does.
 *
 * `loadGameScripts({ include })` lets each test load only the subset
 * of *classic* JS files it needs. Data is already loaded by the static
 * imports below.
 *
 * Later ESM phases (5b, 5c, ...) will convert the js/* files too and
 * this whole eval-based loader will go away.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Side-effect imports: each data module writes its global to window.
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

const __filename = fileURLToPath(import.meta.url);
const ROOT = resolve(__filename, '..', '..');

// Default load order matches the order in index.html. Only classic js/*
// files now — data is handled by the static imports above.
export const CORE_SCRIPTS = [
  'js/constants.js',
];

const evalGlobal = (src) => (0, eval)(src);

export function loadGameScripts({ include = CORE_SCRIPTS } = {}) {
  for (const rel of include) {
    const path = resolve(ROOT, rel);
    let src;
    try {
      src = readFileSync(path, 'utf-8');
    } catch (err) {
      throw new Error(`Test setup: could not read ${rel}: ${err.message}`);
    }
    try {
      evalGlobal(src);
    } catch (err) {
      throw new Error(`Test setup: error evaluating ${rel}: ${err.message}`);
    }
  }
}

loadGameScripts();
