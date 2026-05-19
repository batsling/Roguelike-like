/**
 * Tests for predictPlayerIncomingDamage in js/combat-engine.js.
 *
 * The dice tray UI uses this helper to paint the FINAL post-modifier
 * damage on each enemy die (the "die face = final damage" rule). The math
 * here must match what dealDamageToPlayer actually applies — otherwise the
 * displayed value drifts from the damage taken, which is the regression the
 * player reported.
 */

import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { loadGameScripts } from './setup.js';

beforeAll(() => {
  globalThis.window = globalThis;
  globalThis.gameState = globalThis.gameState || { deck: [], inventory: [], spells: [], maxEnergy: 2 };
  globalThis.inventory = [];
  globalThis.health = 50;
  globalThis.maxHealth = 50;
  globalThis.gold = 0;
  globalThis.StateMutator = globalThis.StateMutator || {
    addItem: () => {},
    setHealth: (v) => { globalThis.health = v; },
    modifyMaxHealth: () => {},
    modifyHealth: () => {},
    subscribe: () => () => {},
    _notify: () => {},
  };
  globalThis.saveCurrentGame = () => {};
  globalThis.createNotification = () => {};
  loadGameScripts({ include: ['js/combat-engine.js'] });
  if (typeof globalThis.HAND_SIZE_LIMIT === 'undefined') globalThis.HAND_SIZE_LIMIT = 10;
});

function makeState(playerStatuses = {}, enemyStatuses = {}) {
  globalThis.combatState = {
    player: {
      health: 50, maxHealth: 50, energy: 3, maxEnergy: 3,
      block: 0, statuses: { ...playerStatuses },
      stats: { strength: 0, dexterity: 0, intelligence: 0, charisma: 0 },
      bonuses: { strength: 0, dexterity: 0, intelligence: 0, charisma: 0 },
    },
    enemies: [],
    allies: [],
    log: [],
    phase: 'enemy_actions',
  };
  return {
    id: 'enemy_test',
    name: 'Dummy',
    statuses: { ...enemyStatuses },
  };
}

beforeEach(() => {
  globalThis.health = 50;
  globalThis.maxHealth = 50;
  globalThis.inventory = [];
});

describe('predictPlayerIncomingDamage — modifier chain', () => {
  it('returns raw damage when there are no modifiers', () => {
    const e = makeState();
    expect(globalThis.predictPlayerIncomingDamage(7, ['melee'], e)).toBe(7);
  });

  it('adds enemy Power to outgoing damage', () => {
    const e = makeState({}, { power: 3 });
    expect(globalThis.predictPlayerIncomingDamage(5, ['melee'], e)).toBe(8);
  });

  it('adds enemy Thorns to melee attacks only', () => {
    const e = makeState({}, { thorns: 2 });
    expect(globalThis.predictPlayerIncomingDamage(5, ['melee'], e)).toBe(7);
    expect(globalThis.predictPlayerIncomingDamage(5, ['ranged'], e)).toBe(5);
  });

  it('Vulnerable scales incoming damage ×1.5 (ceil)', () => {
    const e = makeState({ vulnerable: 1 });
    expect(globalThis.predictPlayerIncomingDamage(5, ['melee'], e)).toBe(8);   // ceil(7.5) = 8
    expect(globalThis.predictPlayerIncomingDamage(10, ['melee'], e)).toBe(15);
  });

  it('Enfeebled doubles incoming damage', () => {
    const e = makeState({ enfeebled: 1 });
    expect(globalThis.predictPlayerIncomingDamage(4, ['melee'], e)).toBe(8);
  });

  it('Bruise adds flat per-hit damage', () => {
    const e = makeState({ bruise: 3 });
    expect(globalThis.predictPlayerIncomingDamage(5, ['melee'], e)).toBe(8);
  });

  it('Brace clamps damage to max(1, damage - stacks)', () => {
    const e1 = makeState({ brace: 4 });
    expect(globalThis.predictPlayerIncomingDamage(10, ['melee'], e1)).toBe(6);
    const e2 = makeState({ brace: 99 });
    expect(globalThis.predictPlayerIncomingDamage(5, ['melee'], e2)).toBe(1);  // floor at 1
  });

  it('Dodge fully negates the hit', () => {
    const e = makeState({ dodge: 1 });
    expect(globalThis.predictPlayerIncomingDamage(20, ['melee'], e)).toBe(0);
  });

  it('Intangible clamps incoming to 1', () => {
    const e = makeState({ intangible: 1 });
    expect(globalThis.predictPlayerIncomingDamage(50, ['melee'], e)).toBe(1);
  });

  it('combines modifiers in the right order (Power → Vulnerable)', () => {
    // raw 5, +Power 3 = 8, ×Vuln 1.5 = ceil(12) = 12, +Bruise 2 = 14
    const e = makeState({ vulnerable: 1, bruise: 2 }, { power: 3 });
    expect(globalThis.predictPlayerIncomingDamage(5, ['melee'], e)).toBe(14);
  });

  it('matches what dealDamageToPlayer actually deals', () => {
    // The whole point of this helper — its output must equal what the
    // engine produces. Set up a state, predict, then run the real damage
    // function and compare the HP delta.
    const e = makeState({ vulnerable: 1 }, { power: 2 });
    const predicted = globalThis.predictPlayerIncomingDamage(6, ['melee'], e);

    // Snapshot player HP, run real damage, measure delta
    const before = globalThis.combatState.player.health;
    globalThis.combatState.player.block = 0;
    // Mirror what executeEnemyActions does: add Power BEFORE calling
    // dealDamageToPlayer. predictPlayerIncomingDamage folds it in, so we
    // pass the raw+power value to keep them comparable.
    globalThis.dealDamageToPlayer(6 + 2, ['melee'], e);
    const taken = before - globalThis.combatState.player.health;
    expect(taken).toBe(predicted);
  });
});
