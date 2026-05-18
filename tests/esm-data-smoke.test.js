import { describe, it, expect } from 'vitest';

describe('Phase 5a — data modules expose globals after ESM import', () => {
  it('CARDS_DATA is loaded with hundreds of cards', () => {
    expect(Array.isArray(globalThis.CARDS_DATA)).toBe(true);
    expect(globalThis.CARDS_DATA.length).toBeGreaterThan(100);
  });

  it('ITEMS_DATA is loaded with dozens of items', () => {
    expect(Array.isArray(globalThis.ITEMS_DATA)).toBe(true);
    expect(globalThis.ITEMS_DATA.length).toBeGreaterThan(50);
  });

  it('GAMES_DATA is loaded with many games', () => {
    expect(Array.isArray(globalThis.GAMES_DATA)).toBe(true);
    expect(globalThis.GAMES_DATA.length).toBeGreaterThan(500);
  });

  it('FISH_DATA is loaded (was a latent ReferenceError before Phase 5a)', () => {
    expect(Array.isArray(globalThis.FISH_DATA)).toBe(true);
  });

  it('BINGO_GOALS_DATA is loaded', () => {
    expect(Array.isArray(globalThis.BINGO_GOALS_DATA)).toBe(true);
  });
});
