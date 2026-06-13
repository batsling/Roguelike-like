/**
 * Tests that poison on the player:
 *   1. Bypasses block — damage goes straight to HP regardless of how much
 *      block the player has stockpiled.
 *   2. Fires at the START of the player's turn, not at the end and not
 *      during enemy actions.
 *   3. Decays by 1 stack at end of player turn (existing decay behavior).
 *
 * Pins both behaviors so a refactor of processStatusEffects can't quietly
 * regress this.
 */

import { describe, it, expect, beforeAll, beforeEach } from 'vitest';
import { loadGameScripts } from './setup.js';

beforeAll(() => {
  globalThis.window = globalThis;
  globalThis.gameState = { deck: [], inventory: [], spells: [], maxEnergy: 2 };
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

function makeState(playerOverrides = {}) {
  globalThis.combatState = {
    player: {
      health: 50, maxHealth: 50, energy: 3, maxEnergy: 3,
      block: 0, statuses: {},
      stats: { strength: 0, dexterity: 0, intelligence: 0, charisma: 0 },
      bonuses: { strength: 0, dexterity: 0, intelligence: 0, charisma: 0 },
      ...playerOverrides,
    },
    enemies: [],
    allies: [],
    log: [],
    phase: 'player_action',
  };
}

beforeEach(() => {
  globalThis.health = 50;
  globalThis.maxHealth = 50;
});

describe('Player poison — bypasses block', () => {
  it('full block does NOT absorb poison damage', () => {
    makeState({ block: 100, statuses: { poison: 4 } });
    const before = globalThis.combatState.player.health;
    globalThis.processStatusEffects(globalThis.combatState.player, 'start');
    // Block is irrelevant; HP drops by full poison stacks
    expect(globalThis.combatState.player.health).toBe(before - 4);
    expect(globalThis.combatState.player.block).toBe(100);  // block untouched
  });

  it('zero block still takes the same poison damage', () => {
    makeState({ block: 0, statuses: { poison: 4 } });
    const before = globalThis.combatState.player.health;
    globalThis.processStatusEffects(globalThis.combatState.player, 'start');
    expect(globalThis.combatState.player.health).toBe(before - 4);
  });

  it('scales with the stack count', () => {
    makeState({ statuses: { poison: 7 } });
    const before = globalThis.combatState.player.health;
    globalThis.processStatusEffects(globalThis.combatState.player, 'start');
    expect(globalThis.combatState.player.health).toBe(before - 7);
  });

  it('Vulnerable does NOT amplify poison damage (poison is pure)', () => {
    makeState({ statuses: { poison: 4, vulnerable: 2 } });
    const before = globalThis.combatState.player.health;
    globalThis.processStatusEffects(globalThis.combatState.player, 'start');
    // Straight 4, not ceil(4 * 1.5) = 6
    expect(globalThis.combatState.player.health).toBe(before - 4);
  });
});

describe('Player poison — start-of-turn timing', () => {
  it('fires at timing="start"', () => {
    makeState({ statuses: { poison: 3 } });
    const before = globalThis.combatState.player.health;
    globalThis.processStatusEffects(globalThis.combatState.player, 'start');
    expect(globalThis.combatState.player.health).toBe(before - 3);
  });

  it('does NOT fire damage at timing="end" (end is for decay only)', () => {
    makeState({ statuses: { poison: 3 } });
    const before = globalThis.combatState.player.health;
    globalThis.processStatusEffects(globalThis.combatState.player, 'end');
    // No damage at end-of-turn — just decay
    expect(globalThis.combatState.player.health).toBe(before);
  });

  it('decays by 1 stack at end of turn', () => {
    makeState({ statuses: { poison: 3 } });
    globalThis.processStatusEffects(globalThis.combatState.player, 'end');
    expect(globalThis.combatState.player.statuses['poison']).toBe(2);
  });

  it('1-stack poison decays to gone at end of turn', () => {
    makeState({ statuses: { poison: 1 } });
    globalThis.processStatusEffects(globalThis.combatState.player, 'end');
    expect(globalThis.combatState.player.statuses['poison']).toBeFalsy();
  });
});

describe('Player poison — full-turn cycle', () => {
  it('start fires 3 damage, end decays to 2, next start fires 2 more', () => {
    makeState({ statuses: { poison: 3 } });
    const startHp = globalThis.combatState.player.health;

    // Turn N start
    globalThis.processStatusEffects(globalThis.combatState.player, 'start');
    expect(globalThis.combatState.player.health).toBe(startHp - 3);
    expect(globalThis.combatState.player.statuses['poison']).toBe(3);  // not decayed yet

    // Turn N end — decay
    globalThis.processStatusEffects(globalThis.combatState.player, 'end');
    expect(globalThis.combatState.player.statuses['poison']).toBe(2);

    // Turn N+1 start — fire at new stack count
    globalThis.processStatusEffects(globalThis.combatState.player, 'start');
    expect(globalThis.combatState.player.health).toBe(startHp - 3 - 2);
    expect(globalThis.combatState.player.statuses['poison']).toBe(2);

    // Turn N+1 end — decay again
    globalThis.processStatusEffects(globalThis.combatState.player, 'end');
    expect(globalThis.combatState.player.statuses['poison']).toBe(1);

    // Turn N+2 start
    globalThis.processStatusEffects(globalThis.combatState.player, 'start');
    expect(globalThis.combatState.player.health).toBe(startHp - 3 - 2 - 1);

    // Turn N+2 end — fully decays
    globalThis.processStatusEffects(globalThis.combatState.player, 'end');
    expect(globalThis.combatState.player.statuses['poison']).toBeFalsy();
  });
});
