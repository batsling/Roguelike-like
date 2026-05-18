/**
 * Test harness.
 *
 * The 20 data files in data/*.js are dual-mode: they use `const X = ...`
 * + `if (typeof window !== 'undefined') window.X = X;` at the bottom so
 * they work both as classic <script> tags (in index.html) AND as ESM
 * side-effect imports (here in the test setup).
 *
 * Phase 5a tried to convert the data layer to a single <script
 * type="module"> entry but discovered that classic <script defer> tags
 * race the deferred module's async fetch tree — defer scripts may
 * execute BEFORE the module's data imports complete, leaving data
 * globals undefined. Reverted. Full Phase 5 will need to convert the
 * whole js/* tree to modules at once.
 *
 * The js/* files are still classic <script> bodies. To run them under
 * Vitest+jsdom we read each file and indirect-eval it in global scope,
 * mirroring what a <script> tag does. Tests can call
 * loadGameScripts({ include: [...] }) to load whichever subset they need.
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
