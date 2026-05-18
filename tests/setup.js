/**
 * Phase 0 test harness.
 *
 * The existing codebase is loaded via <script> tags in the browser. The files
 * use `var` declarations at file scope and assume `globalThis === window`.
 * To run them under Vitest+jsdom we read each file and indirect-eval it in
 * global scope, which mirrors what a <script> tag does.
 *
 * `loadGameScripts({ include })` lets each test load only the subset of files
 * it needs. The default `include` list is the minimum to exercise the combat
 * engine and data helpers — keep it small.
 *
 * When we adopt ESM in Phase 5, this whole file goes away in favor of plain
 * import statements.
 */

import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const ROOT = resolve(__filename, '..', '..');

// Default load order matches the order in index.html. Trimmed to the
// scripts that combat / data tests actually need.
export const CORE_SCRIPTS = [
  'data/spell-keywords-data.js',
  'data/cards-data.js',
  'data/dice-data.js',
  'data/items-data.js',
  'data/enemies-data.js',
  'data/statuses-data.js',
  'data/spells-data.js',
  'data/moves-data.js',
  'data/addons-data.js',
  'data/characters-data.js',
  'data/weapons-data.js',
  'data/curses-data.js',
  'data/game-statuses-data.js',
  'data/scrolls-data.js',
  'data/potions-data.js',
  'data/allies-data.js',
  'data/fish-data.js',
  'js/constants.js',
];

// Indirect eval so `var` declarations attach to globalThis (= jsdom window).
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

// Auto-load core data on import. Tests that need more (combat-engine etc.)
// can call loadGameScripts({ include: [...] }) themselves.
loadGameScripts();
