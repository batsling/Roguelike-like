/**
 * Tests for the persistent player d20 in gameState.
 *
 * Behavior under test:
 *   - createD20() returns a 20-sided die with sides[i].value = i+1
 *   - Items will mutate sides[i].value / displayValue to modify faces;
 *     the dice-renderer reads displayValue when painting face textures
 *     (smoke-tested via direct read of the data shape)
 *   - The polyhedral face-texture builder uses side.displayValue if set,
 *     falling back to the conventional face value
 *
 * The renderer class itself needs WebGL and isn't tested here; the geometry
 * + numbering helpers (already tested in dice-polyhedra.test.js) and the
 * per-side override path are what matter for item integration.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const ROOT = resolve(__filename, '..', '..');

// Stub THREE for any modules that touch it during eval (none execute on load,
// but createPolyhedralFaceTexture creates a CanvasTexture when called — we
// only invoke the helpers, not the texture builder, in these tests).
class V3 {
  constructor(x = 0, y = 0, z = 0) { this.x = x; this.y = y; this.z = z; }
  set(x, y, z) { this.x = x; this.y = y; this.z = z; return this; }
  clone() { return new V3(this.x, this.y, this.z); }
  add(v) { this.x += v.x; this.y += v.y; this.z += v.z; return this; }
  subVectors(a, b) { this.x = a.x - b.x; this.y = a.y - b.y; this.z = a.z - b.z; return this; }
  crossVectors(a, b) {
    const x = a.y * b.z - a.z * b.y;
    const y = a.z * b.x - a.x * b.z;
    const z = a.x * b.y - a.y * b.x;
    this.x = x; this.y = y; this.z = z;
    return this;
  }
  dot(v) { return this.x * v.x + this.y * v.y + this.z * v.z; }
  length() { return Math.sqrt(this.dot(this)); }
  multiplyScalar(s) { this.x *= s; this.y *= s; this.z *= s; return this; }
  negate() { this.x = -this.x; this.y = -this.y; this.z = -this.z; return this; }
  normalize() {
    const l = this.length() || 1;
    this.x /= l; this.y /= l; this.z /= l;
    return this;
  }
}

beforeAll(() => {
  globalThis.THREE = { Vector3: V3 };

  // Pull in createD20 from dice-system.js
  const diceSystemSrc = readFileSync(resolve(ROOT, 'js/dice-system.js'), 'utf-8');
  (0, eval)(diceSystemSrc);
});

describe('createD20 — dice-system.js', () => {
  it('returns a d20 with 20 sides', () => {
    const d = globalThis.createD20();
    expect(d.type).toBe('d20');
    expect(d.sides.length).toBe(20);
  });

  it('each side has value, texture, modifiers, displayValue fields', () => {
    const d = globalThis.createD20();
    for (let i = 0; i < d.sides.length; i++) {
      expect(d.sides[i]).toHaveProperty('value');
      expect(d.sides[i]).toHaveProperty('texture');
      expect(d.sides[i]).toHaveProperty('modifiers');
      expect(d.sides[i]).toHaveProperty('displayValue');
      expect(Array.isArray(d.sides[i].modifiers)).toBe(true);
    }
  });

  it('default side values are 1..20 in order', () => {
    const d = globalThis.createD20();
    for (let i = 0; i < 20; i++) {
      expect(d.sides[i].value).toBe(i + 1);
    }
  });

  it('exposes globalModifiers and currentRoll for run-wide effects', () => {
    const d = globalThis.createD20();
    expect(Array.isArray(d.globalModifiers)).toBe(true);
    expect(d.currentRoll).toBeNull();
  });
});

describe('Item integration shape — face-modification API surface', () => {
  it('items can override displayValue without touching value', () => {
    const d = globalThis.createD20();
    // Simulate "Lucky Charm: face 1 displays as 20"
    d.sides[0].displayValue = 20;
    expect(d.sides[0].value).toBe(1);
    expect(d.sides[0].displayValue).toBe(20);
  });

  it('items can also overwrite value directly for mechanical changes', () => {
    const d = globalThis.createD20();
    // Simulate "Loaded Die: face 1 IS a 20 mechanically too"
    d.sides[0].value = 20;
    expect(d.sides[0].value).toBe(20);
    expect(d.sides[0].displayValue).toBeNull();
  });

  it('items can stack modifiers on individual sides', () => {
    const d = globalThis.createD20();
    d.sides[5].modifiers.push({ kind: 'gold_on_roll', amount: 10 });
    d.sides[5].modifiers.push({ kind: 'heal_on_roll', amount: 3 });
    expect(d.sides[5].modifiers.length).toBe(2);
  });

  it('global modifiers are independent of per-face state', () => {
    const d = globalThis.createD20();
    d.globalModifiers.push({ kind: 'plus_n_to_all_rolls', amount: 2 });
    expect(d.globalModifiers.length).toBe(1);
    // Sides remain pristine
    expect(d.sides[0].value).toBe(1);
  });
});

describe('_rollD20 — reads face values from the persistent d20', () => {
  // Pull just the _rollD20 function out of event-engine.js. The file has
  // lots of other globals it pokes at on load; we extract the function
  // source and eval it in isolation to avoid those side effects.
  beforeAll(() => {
    const src = readFileSync(resolve(ROOT, 'js/event-engine.js'), 'utf-8');
    // Match the function body. The regex is broad enough to survive small
    // tweaks but tight enough to pull only this one function.
    const m = src.match(/function _rollD20\(mode\) \{[\s\S]*?^\}/m);
    if (!m) throw new Error('Could not extract _rollD20 from event-engine.js');
    (0, eval)(m[0]);
  });

  it('falls back to a plain 1..20 roll when no gameState.playerD20 exists', () => {
    delete globalThis.gameState;
    const seen = new Set();
    for (let i = 0; i < 100; i++) seen.add(globalThis._rollD20('normal').used);
    for (const v of seen) {
      expect(v).toBeGreaterThanOrEqual(1);
      expect(v).toBeLessThanOrEqual(20);
    }
  });

  it('reads side.value from gameState.playerD20 when present', () => {
    // Build a "rigged" d20 where every face is 20
    const sides = Array.from({ length: 20 }, () => ({
      value: 20, texture: null, modifiers: [], displayValue: null,
    }));
    globalThis.gameState = { playerD20: { type: 'd20', sides, globalModifiers: [], currentRoll: null } };
    for (let i = 0; i < 30; i++) {
      expect(globalThis._rollD20('normal').used).toBe(20);
    }
  });

  it('side.displayValue overrides value for the roll outcome', () => {
    // Default 1..20 sides, but face 0 has displayValue = 100
    const d = globalThis.createD20();
    d.sides[0].displayValue = 100;
    globalThis.gameState = { playerD20: d };
    // Force the random pick to land on index 0 deterministically
    const origRandom = Math.random;
    Math.random = () => 0;  // floor(0 * 20) = 0
    try {
      expect(globalThis._rollD20('normal').used).toBe(100);
    } finally {
      Math.random = origRandom;
    }
  });

  it('advantage picks the higher of two rolls', () => {
    globalThis.gameState = { playerD20: globalThis.createD20() };
    const origRandom = Math.random;
    const seq = [0.05, 0.95];  // → indices 1, 19 → values 2, 20
    let i = 0;
    Math.random = () => seq[i++ % seq.length];
    try {
      const r = globalThis._rollD20('advantage');
      expect(r.used).toBe(20);
      expect(r.rolls).toEqual([2, 20]);
    } finally {
      Math.random = origRandom;
    }
  });

  it('disadvantage picks the lower of two rolls', () => {
    globalThis.gameState = { playerD20: globalThis.createD20() };
    const origRandom = Math.random;
    const seq = [0.95, 0.05];  // → indices 19, 1 → values 20, 2
    let i = 0;
    Math.random = () => seq[i++ % seq.length];
    try {
      const r = globalThis._rollD20('disadvantage');
      expect(r.used).toBe(2);
    } finally {
      Math.random = origRandom;
    }
  });
});

describe('Polyhedral face texture — displayValue override', () => {
  // We can't easily render the canvas in jsdom, but we can verify that
  // _buildPolyhedronFaceData + _assignFaceValues still produce predictable
  // mapping so an item that sets sides[i].displayValue = X is wired to a
  // specific geometric face.
  beforeAll(() => {
    const rendererSrc = readFileSync(resolve(ROOT, 'js/dice-renderer.js'), 'utf-8');
    (0, eval)(rendererSrc);
  });

  it('every face value 1..N maps to exactly one geometric face', () => {
    for (const sides of [4, 6, 8, 10, 12]) {
      const fd = globalThis._buildPolyhedronFaceData(sides, 1);
      const values = globalThis._assignFaceValues(fd, sides);
      const seen = new Set(values);
      expect(seen.size).toBe(sides);
    }
  });

  it('a future "set displayValue" on a side does not break face count', () => {
    // This documents the contract: items setting displayValue on
    // diceData.sides[i] leave the face count and ordering unchanged. The
    // renderer reads side.displayValue in createPolyhedralFaceTexture for
    // the visual override; rotation logic uses the conventional value.
    const d = globalThis.createD20();
    d.sides[0].displayValue = 99;
    d.sides[7].displayValue = 'X';
    expect(d.sides.length).toBe(20);
  });
});
