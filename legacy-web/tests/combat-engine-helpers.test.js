/**
 * Pure-helper tests against js/combat-engine.js.
 *
 * These functions are state-free: they take a string in, return a value out.
 * They're the easiest combat-engine surface to pin behavior on now, before
 * the larger Phase 1+ refactor moves stat reads through StateMutator.
 *
 * If any of these regress, the enemy ability/intent parser is broken.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { loadGameScripts } from './setup.js';

beforeAll(() => {
  loadGameScripts({ include: ['js/combat-engine.js'] });
});

describe('parseStaggerThreshold', () => {
  it('returns null when ability is missing or empty', () => {
    expect(globalThis.parseStaggerThreshold('')).toBeNull();
    expect(globalThis.parseStaggerThreshold(null)).toBeNull();
    expect(globalThis.parseStaggerThreshold(undefined)).toBeNull();
  });

  it('returns null when no Stagger clause is present', () => {
    expect(globalThis.parseStaggerThreshold('Curl Up 5')).toBeNull();
  });

  it('parses a whole-percent threshold to a 0-1 fraction', () => {
    expect(globalThis.parseStaggerThreshold('Stagger 33%')).toBeCloseTo(0.33);
    expect(globalThis.parseStaggerThreshold('Stagger 50%')).toBeCloseTo(0.5);
    expect(globalThis.parseStaggerThreshold('Stagger 100%')).toBeCloseTo(1.0);
  });

  it('parses fractional percent thresholds', () => {
    expect(globalThis.parseStaggerThreshold('Stagger 12.5%')).toBeCloseTo(0.125);
  });

  it('finds a stagger clause among other ability clauses', () => {
    expect(
      globalThis.parseStaggerThreshold('Curl Up 5, Stagger 25%, Thorns 2'),
    ).toBeCloseTo(0.25);
  });
});

describe('parseSplitAbility', () => {
  it('returns null when no split clause is present', () => {
    expect(globalThis.parseSplitAbility('')).toBeNull();
    expect(globalThis.parseSplitAbility('Stagger 50%')).toBeNull();
  });

  it('parses "Split N Name" into { count, spawnName }', () => {
    const result = globalThis.parseSplitAbility('Split 2 Acid Slime (M)');
    expect(result).toMatchObject({ count: 2, spawnName: 'Acid Slime (M)' });
  });
});

describe('parseStartingAbilities', () => {
  it('returns an empty object for missing or N/A abilities', () => {
    expect(globalThis.parseStartingAbilities('')).toEqual({});
    expect(globalThis.parseStartingAbilities('N/A')).toEqual({});
    expect(globalThis.parseStartingAbilities(null)).toEqual({});
  });

  it('parses "Fading N" as a fading status', () => {
    expect(globalThis.parseStartingAbilities('Fading 3')).toEqual({ fading: 3 });
  });

  it('parses "Multi Attack N" as a multi_attack status', () => {
    expect(globalThis.parseStartingAbilities('Multi Attack 2')).toEqual({
      multi_attack: 2,
    });
  });

  it('parses "Curl Up N" as a curl_up status', () => {
    expect(globalThis.parseStartingAbilities('Curl Up 5')).toEqual({ curl_up: 5 });
  });

  it('does not add stagger to statuses (handled separately)', () => {
    expect(globalThis.parseStartingAbilities('Stagger 33%')).toEqual({});
  });

  it('skips "When Defeated, ..." clauses entirely', () => {
    expect(
      globalThis.parseStartingAbilities('When Defeated, 50% Spawn Gusher'),
    ).toEqual({});
  });

  it('does not include split clauses (handled by parseSplitAbility)', () => {
    const result = globalThis.parseStartingAbilities('Split 2 Acid Slime (M)');
    expect(result).toEqual({});
  });

  it('converts "Immune to X" to immune_x flag', () => {
    expect(globalThis.parseStartingAbilities('Immune to Fire')).toEqual({
      immune_fire: 1,
    });
  });

  it('parses "N StatusName" as a snake_case status with value N', () => {
    expect(globalThis.parseStartingAbilities('3 Thorns')).toEqual({ thorns: 3 });
  });

  it('parses bare named abilities as snake_case keys with value 1', () => {
    expect(globalThis.parseStartingAbilities('Pigment Rich')).toEqual({
      pigment_rich: 1,
    });
    expect(globalThis.parseStartingAbilities('Barricade')).toEqual({ barricade: 1 });
  });

  it('handles multi-clause abilities (slash and comma separated)', () => {
    const result = globalThis.parseStartingAbilities(
      'Curl Up 4, Stagger 33% / 3 Thorns',
    );
    expect(result).toEqual({ curl_up: 4, thorns: 3 });
  });
});

describe('hasDiceNotation', () => {
  it('detects dice notation in a string', () => {
    expect(globalThis.hasDiceNotation('Deal D6 damage')).toBe(true);
    expect(globalThis.hasDiceNotation('Deal D8x2')).toBe(true);
    expect(globalThis.hasDiceNotation('d10')).toBe(true);
  });

  it('returns false on plain text', () => {
    expect(globalThis.hasDiceNotation('Deal 6 damage')).toBe(false);
    expect(globalThis.hasDiceNotation('')).toBe(false);
  });
});

describe('rollDiceNotation', () => {
  it('rolls a single die within the expected range', () => {
    for (let i = 0; i < 50; i++) {
      const { total, rolls } = globalThis.rollDiceNotation('D6');
      expect(rolls.length).toBe(1);
      expect(total).toBeGreaterThanOrEqual(1);
      expect(total).toBeLessThanOrEqual(6);
    }
  });

  it('rolls the right number of dice for "D8x3"', () => {
    const { rolls, total } = globalThis.rollDiceNotation('D8x3');
    expect(rolls.length).toBe(3);
    expect(total).toBeGreaterThanOrEqual(3);
    expect(total).toBeLessThanOrEqual(24);
  });

  it('rolls all groups in a compound notation like "D8x2 + D6x2"', () => {
    const { rolls } = globalThis.rollDiceNotation('D8x2 + D6x2');
    expect(rolls.length).toBe(4);
    const d8s = rolls.filter((r) => r.die === 8);
    const d6s = rolls.filter((r) => r.die === 6);
    expect(d8s.length).toBe(2);
    expect(d6s.length).toBe(2);
  });
});
