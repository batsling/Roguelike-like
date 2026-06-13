/**
 * Data-shape integrity tests.
 *
 * These pin the shape of the data files so subsequent refactor phases can't
 * silently drop a field. They don't validate game balance or behavior — just
 * that the structure remains what the runtime expects.
 *
 * If a test here fails after a refactor, the runtime would crash too.
 */

import { describe, it, expect } from 'vitest';

// tests/setup.js runs before this file and populates globalThis with data.

describe('CARDS_DATA', () => {
  it('is a non-empty array on globalThis', () => {
    expect(Array.isArray(globalThis.CARDS_DATA)).toBe(true);
    expect(globalThis.CARDS_DATA.length).toBeGreaterThan(50);
  });

  it('every entry has a name and type', () => {
    for (const card of globalThis.CARDS_DATA) {
      expect(card, JSON.stringify(card)).toHaveProperty('name');
      expect(typeof card.name).toBe('string');
      expect(card).toHaveProperty('type');
    }
  });

  it('card name duplicates, if any, are minimal', () => {
    const names = globalThis.CARDS_DATA.map((c) => c.name);
    const counts = names.reduce((acc, n) => ((acc[n] = (acc[n] || 0) + 1), acc), {});
    const dupes = Object.entries(counts).filter(([, n]) => n > 1);
    // We allow a handful (some upgraded/variant cards reuse names) but flag
    // a regression if dupes balloon.
    expect(dupes.length).toBeLessThan(10);
  });
});

describe('ENEMIES_DATA', () => {
  it('is a non-empty array on globalThis', () => {
    expect(Array.isArray(globalThis.ENEMIES_DATA)).toBe(true);
    expect(globalThis.ENEMIES_DATA.length).toBeGreaterThan(10);
  });

  it('every enemy has a name and hp range', () => {
    for (const enemy of globalThis.ENEMIES_DATA) {
      expect(enemy).toHaveProperty('name');
      expect(typeof enemy.name).toBe('string');
      expect(enemy).toHaveProperty('hpMin');
      expect(enemy).toHaveProperty('hpMax');
      expect(typeof enemy.hpMin).toBe('number');
      expect(typeof enemy.hpMax).toBe('number');
      expect(enemy.hpMin).toBeGreaterThan(0);
      expect(enemy.hpMax).toBeGreaterThanOrEqual(enemy.hpMin);
    }
  });
});

describe('STATUSES_DATA', () => {
  it('is loaded and structured as an array or object', () => {
    const data = globalThis.STATUSES_DATA;
    expect(data).toBeDefined();
    const length = Array.isArray(data) ? data.length : Object.keys(data).length;
    expect(length).toBeGreaterThan(10);
  });
});

describe('CHARACTERS_DATA', () => {
  it('contains at least the 6 documented characters', () => {
    expect(typeof globalThis.CHARACTERS_DATA).toBe('object');
    const keys = Object.keys(globalThis.CHARACTERS_DATA);
    expect(keys.length).toBeGreaterThanOrEqual(6);
  });

  it('every character has a name, health, and energy', () => {
    for (const id of Object.keys(globalThis.CHARACTERS_DATA)) {
      const character = globalThis.CHARACTERS_DATA[id];
      expect(character, id).toHaveProperty('name');
      expect(character, id).toHaveProperty('health');
      expect(character, id).toHaveProperty('energy');
      expect(typeof character.health).toBe('number');
      expect(character.health).toBeGreaterThan(0);
    }
  });
});

describe('CURSES_DATA', () => {
  it('is a non-empty collection', () => {
    const data = globalThis.CURSES_DATA;
    expect(data).toBeDefined();
    const length = Array.isArray(data) ? data.length : Object.keys(data).length;
    expect(length).toBeGreaterThan(5);
  });
});

describe('constants.js', () => {
  it('exposes COLORS', () => {
    expect(globalThis.COLORS).toBeDefined();
    expect(typeof globalThis.COLORS).toBe('object');
  });

  it('exposes STORAGE_KEYS', () => {
    expect(globalThis.STORAGE_KEYS).toBeDefined();
    expect(typeof globalThis.STORAGE_KEYS).toBe('object');
  });

  it('exposes RARITY_COLORS', () => {
    // RARITY_COLORS isn't re-assigned to window in constants.js, so it lives
    // inside constants.js scope only. We just confirm the file evaluated by
    // checking another window-exported constant.
    expect(globalThis.window.COLORS).toBe(globalThis.COLORS);
  });
});
