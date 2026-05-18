/**
 * Tests for the Phase 1 subscription mechanism in js/state-mutator.js.
 *
 * The mutator file uses bare globals (health, gold, inventory, gameState,
 * curses) and a few UI / notification helpers. We stub the minimum
 * required surface on globalThis before evaluating the file.
 */

import { describe, it, expect, beforeEach, vi } from 'vitest';
import { loadGameScripts } from './setup.js';

function stubMutatorGlobals() {
  // Bare-global state the mutator reads/writes.
  globalThis.health = 10;
  globalThis.maxHealth = 10;
  globalThis.gold = 0;
  globalThis.discovery = 0;
  globalThis.strength = 0;
  globalThis.dexterity = 0;
  globalThis.intelligence = 0;
  globalThis.charisma = 0;
  globalThis.luck = 0;
  globalThis.skip = 0;
  globalThis.reroll = 0;
  globalThis.dash = 0;
  globalThis.inventory = [];
  globalThis.curses = [];
  globalThis.gameState = {
    health: 10,
    maxHealth: 10,
    gold: 0,
    maxEnergy: 2,
    inventory: [],
    activeCurses: [],
  };

  // UI helpers are optional in the mutator (typeof checks); we leave them
  // undefined so we only observe the new _notify behaviour, not the legacy
  // explicit calls.
  delete globalThis.updateTopBar;
  delete globalThis.updateGameStats;
  delete globalThis.updateInventory;
  delete globalThis.updateCursesDisplay;
  delete globalThis.updateHealthDisplay;
  delete globalThis.updateGoldDisplay;
  delete globalThis.updateAbilitiesDisplay;
  delete globalThis.createNotification;
  delete globalThis.enforceRockBottom;
  delete globalThis.triggerOnCurseRemoved;
}

async function flushMicrotasks() {
  // queueMicrotask drains before the next await Promise.resolve().
  await Promise.resolve();
  await Promise.resolve();
}

beforeEach(() => {
  stubMutatorGlobals();
  // Load (or reload) state-mutator.js so the subscriber set is fresh.
  // Re-evaluating the file re-declares `const StateMutator = {...}` — the
  // first eval succeeds, subsequent ones throw because const can't redeclare.
  // We reset _subscribers / _pendingTags instead.
  if (!globalThis.StateMutator) {
    loadGameScripts({ include: ['js/state-mutator.js'] });
  }
  globalThis.StateMutator._subscribers = new Set();
  globalThis.StateMutator._pendingTags = null;
});

describe('StateMutator subscription mechanism', () => {
  it('exposes subscribe and _notify', () => {
    expect(typeof globalThis.StateMutator.subscribe).toBe('function');
    expect(typeof globalThis.StateMutator._notify).toBe('function');
  });

  it('subscribe returns an unsubscribe function that removes the listener', async () => {
    const fn = vi.fn();
    const unsub = globalThis.StateMutator.subscribe(fn);
    expect(typeof unsub).toBe('function');
    unsub();
    globalThis.StateMutator._notify('health');
    await flushMicrotasks();
    expect(fn).not.toHaveBeenCalled();
  });

  it('notifies subscribers asynchronously (in a microtask), not synchronously', async () => {
    const fn = vi.fn();
    globalThis.StateMutator.subscribe(fn);
    globalThis.StateMutator._notify('health');
    expect(fn).not.toHaveBeenCalled(); // not sync
    await flushMicrotasks();
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('coalesces multiple synchronous _notify calls into one subscriber invocation', async () => {
    const fn = vi.fn();
    globalThis.StateMutator.subscribe(fn);
    globalThis.StateMutator._notify('health');
    globalThis.StateMutator._notify('gold');
    globalThis.StateMutator._notify('inventory');
    await flushMicrotasks();
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it('passes a Set with the union of all tags from the batch', async () => {
    const fn = vi.fn();
    globalThis.StateMutator.subscribe(fn);
    globalThis.StateMutator._notify('health');
    globalThis.StateMutator._notify(['gold', 'inventory']);
    await flushMicrotasks();
    const tags = fn.mock.calls[0][0];
    expect(tags).toBeInstanceOf(Set);
    expect(tags.has('health')).toBe(true);
    expect(tags.has('gold')).toBe(true);
    expect(tags.has('inventory')).toBe(true);
  });

  it('flushes a new batch after the microtask drains', async () => {
    const fn = vi.fn();
    globalThis.StateMutator.subscribe(fn);
    globalThis.StateMutator._notify('health');
    await flushMicrotasks();
    expect(fn).toHaveBeenCalledTimes(1);
    globalThis.StateMutator._notify('gold');
    await flushMicrotasks();
    expect(fn).toHaveBeenCalledTimes(2);
    expect(fn.mock.calls[1][0].has('gold')).toBe(true);
  });

  it('isolates subscriber errors so one bad subscriber does not block others', async () => {
    const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const bad = vi.fn(() => {
      throw new Error('boom');
    });
    const good = vi.fn();
    globalThis.StateMutator.subscribe(bad);
    globalThis.StateMutator.subscribe(good);
    globalThis.StateMutator._notify('health');
    await flushMicrotasks();
    expect(bad).toHaveBeenCalledTimes(1);
    expect(good).toHaveBeenCalledTimes(1);
    expect(consoleSpy).toHaveBeenCalled();
    consoleSpy.mockRestore();
  });
});

describe('StateMutator mutators trigger _notify with correct tags', () => {
  it('modifyHealth notifies with "health"', async () => {
    const fn = vi.fn();
    globalThis.StateMutator.subscribe(fn);
    globalThis.StateMutator.modifyHealth(-3, { updateUI: false });
    await flushMicrotasks();
    expect(fn).toHaveBeenCalledTimes(1);
    expect(fn.mock.calls[0][0].has('health')).toBe(true);
  });

  it('modifyHealth does not notify when delta produces no change', async () => {
    globalThis.health = 0;
    globalThis.gameState.health = 0;
    const fn = vi.fn();
    globalThis.StateMutator.subscribe(fn);
    globalThis.StateMutator.modifyHealth(-3, { updateUI: false });
    await flushMicrotasks();
    expect(fn).not.toHaveBeenCalled();
  });

  it('modifyGold notifies with "gold"', async () => {
    const fn = vi.fn();
    globalThis.StateMutator.subscribe(fn);
    globalThis.StateMutator.modifyGold(+25, { updateUI: false });
    await flushMicrotasks();
    expect(fn).toHaveBeenCalledTimes(1);
    expect(fn.mock.calls[0][0].has('gold')).toBe(true);
  });

  it('modifyMaxHealth notifies with both "maxHealth" and "health"', async () => {
    const fn = vi.fn();
    globalThis.StateMutator.subscribe(fn);
    globalThis.StateMutator.modifyMaxHealth(+5, { updateUI: false });
    await flushMicrotasks();
    const tags = fn.mock.calls[0][0];
    expect(tags.has('maxHealth')).toBe(true);
    expect(tags.has('health')).toBe(true);
  });

  it('modifyStat notifies with "stats" and "stat:<name>"', async () => {
    const fn = vi.fn();
    globalThis.StateMutator.subscribe(fn);
    globalThis.StateMutator.modifyStat('strength', +1, { updateUI: false });
    await flushMicrotasks();
    const tags = fn.mock.calls[0][0];
    expect(tags.has('stats')).toBe(true);
    expect(tags.has('stat:strength')).toBe(true);
  });

  it('addItem notifies with "inventory"', async () => {
    const fn = vi.fn();
    globalThis.StateMutator.subscribe(fn);
    globalThis.StateMutator.addItem('Test Potion', { updateUI: false });
    await flushMicrotasks();
    expect(fn.mock.calls[0][0].has('inventory')).toBe(true);
  });

  it('coalesces multiple mutations within one synchronous block', async () => {
    const fn = vi.fn();
    globalThis.StateMutator.subscribe(fn);
    globalThis.StateMutator.modifyHealth(-2, { updateUI: false });
    globalThis.StateMutator.modifyGold(+10, { updateUI: false });
    globalThis.StateMutator.addItem('A', { updateUI: false });
    await flushMicrotasks();
    expect(fn).toHaveBeenCalledTimes(1);
    const tags = fn.mock.calls[0][0];
    expect(tags.has('health')).toBe(true);
    expect(tags.has('gold')).toBe(true);
    expect(tags.has('inventory')).toBe(true);
  });
});
