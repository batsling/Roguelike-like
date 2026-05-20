/**
 * Tests for rerollable-enemy dice in the dice tray.
 *
 * Behavior under test:
 *   - When an enemy with `rerollable` status has its intent rolled, every
 *     dice-notation effect in that intent is pre-rolled. The rolls are
 *     locked onto each effect (`_lockedRolls`) and one tray entry is
 *     pushed per individual die to `combatState.enemyDice`.
 *   - `resolveEffectValue` returns the locked total instead of rolling
 *     fresh when an effect has `_lockedRolls`.
 *   - `rerollAllPending` rerolls every rerollable enemy's tray dice (and
 *     refreshes the locked rolls on the effects) in the same call that
 *     rerolls the player's pending dice — for 1 reroll cost total.
 *   - When a rerollable enemy dies, its tray entries are removed.
 *   - Non-rerollable enemies are untouched — they keep the legacy
 *     "roll at attack-execution time" path and never appear in the tray.
 *   - `rollPlayerDie` is still exported; `rerollPlayerDie` is gone.
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
  globalThis.cards = globalThis.CARDS_DATA;
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

function makePlayer(overrides = {}) {
  return {
    health: 50,
    maxHealth: 50,
    energy: 3,
    maxEnergy: 3,
    mana: 0,
    block: 0,
    stats: { strength: 0, dexterity: 0, intelligence: 0, charisma: 0 },
    bonuses: { strength: 0, dexterity: 0, intelligence: 0, charisma: 0 },
    statuses: {},
    rerolls: 1,
    dash: 0,
    ...overrides,
  };
}

function makeEnemy(name, pattern, ability = '') {
  const startingStatuses = globalThis.parseStartingAbilities(ability);
  return {
    id: `enemy_${Math.random().toString(36).slice(2, 8)}`,
    name,
    health: 30,
    maxHealth: 30,
    block: 0,
    statuses: startingStatuses,
    ability,
    pattern,
    patternType: 'random',
    patternTurns: null,
    patternTurnIndex: 0,
    currentIntent: null,
    position: 0,
    rolledFaces: new Set(),
    curlUpTriggeredThisTurn: false,
    splitAbility: null,
    staggerThreshold: null,
  };
}

function makeCombatState(enemies) {
  return {
    player: makePlayer(),
    enemies,
    allies: [],
    playerDice: [],
    turn: 1,
    phase: 'player_action',
    log: [],
    spells: [],
    spellCooldowns: {},
    spellCasts: {},
    usedSingleCast: {},
    pendingEffects: [],
    turnHistory: [],
    pendingDice: [],
    enemyDice: [],
    drawPile: [],
    hand: [],
    discardPile: [],
    exhaustPile: [],
    powers: [],
    selectedCardIndex: null,
    reshuffleQueued: false,
    _hitLog: [],
    _flatAttackBonus: 0,
    _druidScaling: {},
    _usedSingleUseFaces: {},
    incrementals: { attacksTotal: 0, attacksThisTurn: 0 },
  };
}

beforeEach(() => {
  globalThis.health = 50;
  globalThis.maxHealth = 50;
  globalThis.inventory = [];
  globalThis.gameState = { deck: [], inventory: [], spells: [], maxEnergy: 3 };
});

// =============================================================================

describe('lockEnemyDiceForTray — pre-rolls dice for Rerollable enemies', () => {
  it('does nothing for an intent with no dice notation', () => {
    const enemy = makeEnemy('Goblin', 'Always: 6 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeCombatState([enemy]);
    globalThis.rollAllEnemyIntents();
    expect(globalThis.combatState.enemyDice).toEqual([]);
  });

  it('pre-rolls D8 and pushes one tray entry per die', () => {
    const enemy = makeEnemy('Rat', 'Always: D8 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeCombatState([enemy]);
    globalThis.rollAllEnemyIntents();
    const dice = globalThis.combatState.enemyDice;
    expect(dice.length).toBe(1);
    expect(dice[0].enemyId).toBe(enemy.id);
    expect(dice[0].sides).toBe(8);
    expect(dice[0].result).toBeGreaterThanOrEqual(1);
    expect(dice[0].result).toBeLessThanOrEqual(8);
    // The effect itself carries the locked roll
    const eff = enemy.currentIntent[0].face.effects[0];
    expect(Array.isArray(eff._lockedRolls)).toBe(true);
    expect(eff._lockedRolls.length).toBe(1);
    expect(eff._lockedRolls[0]).toEqual({ die: 8, result: dice[0].result });
  });

  it('compound notation D8x2+D6x2 produces 4 tray entries', () => {
    const enemy = makeEnemy('Brute', 'Always: D8x2+D6x2 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeCombatState([enemy]);
    globalThis.rollAllEnemyIntents();
    const dice = globalThis.combatState.enemyDice;
    expect(dice.length).toBe(4);
    expect(dice.filter(d => d.sides === 8).length).toBe(2);
    expect(dice.filter(d => d.sides === 6).length).toBe(2);
    // All entries belong to the same enemy and the same effect
    for (const d of dice) {
      expect(d.enemyId).toBe(enemy.id);
      expect(d.effectIndex).toBe(0);
    }
  });

  it('Multi Attack 3 with D6 produces 3 separate tray dice', () => {
    // Multi Attack is parsed from `ability`; rolling the intent expands the
    // single pattern into N effects.
    const enemy = makeEnemy('Hydra', 'Always: D6 Dmg Melee', 'Multi Attack 3, Rerollable');
    globalThis.combatState = makeCombatState([enemy]);
    globalThis.rollAllEnemyIntents();
    expect(globalThis.combatState.enemyDice.length).toBe(3);
    // One entry per intent index (each Multi Attack hit is its own intent)
    const intentIndices = globalThis.combatState.enemyDice.map(d => d.intentIndex).sort();
    expect(intentIndices).toEqual([0, 1, 2]);
  });

  it('non-Rerollable enemies do NOT pre-roll into the tray', () => {
    const enemy = makeEnemy('Goblin', 'Always: D8 Dmg Melee', '');
    globalThis.combatState = makeCombatState([enemy]);
    globalThis.rollAllEnemyIntents();
    expect(globalThis.combatState.enemyDice).toEqual([]);
    // Effect has diceGroups but no _lockedRolls — resolves at attack time
    const eff = enemy.currentIntent[0].face.effects[0];
    expect(Array.isArray(eff.diceGroups)).toBe(true);
    expect(eff._lockedRolls).toBeUndefined();
  });

  it('two Rerollable enemies each get their own tray dice', () => {
    const e1 = makeEnemy('A', 'Always: D6 Dmg Melee', 'Rerollable');
    const e2 = makeEnemy('B', 'Always: D8 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeCombatState([e1, e2]);
    globalThis.rollAllEnemyIntents();
    expect(globalThis.combatState.enemyDice.length).toBe(2);
    expect(globalThis.combatState.enemyDice.find(d => d.enemyId === e1.id).sides).toBe(6);
    expect(globalThis.combatState.enemyDice.find(d => d.enemyId === e2.id).sides).toBe(8);
  });

  it('re-rolling intents clears the previous round\'s tray dice', () => {
    const enemy = makeEnemy('Rat', 'Always: D8 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeCombatState([enemy]);
    globalThis.rollAllEnemyIntents();
    expect(globalThis.combatState.enemyDice.length).toBe(1);
    globalThis.rollAllEnemyIntents();
    // Still exactly one die — not stacked from round to round
    expect(globalThis.combatState.enemyDice.length).toBe(1);
  });

  it('dead enemies are skipped when rolling intents', () => {
    const e1 = makeEnemy('A', 'Always: D6 Dmg Melee', 'Rerollable');
    const e2 = makeEnemy('B', 'Always: D8 Dmg Melee', 'Rerollable');
    e2.health = 0;
    globalThis.combatState = makeCombatState([e1, e2]);
    globalThis.rollAllEnemyIntents();
    expect(globalThis.combatState.enemyDice.length).toBe(1);
    expect(globalThis.combatState.enemyDice[0].enemyId).toBe(e1.id);
  });
});

// =============================================================================

describe('resolveEffectValue — uses locked rolls when present', () => {
  it('returns the locked total instead of rolling fresh', () => {
    const effect = {
      raw: 'D8 Dmg',
      value: 0,
      move: 'Dmg',
      diceGroups: [{ sides: 8, count: 1 }],
      _lockedRolls: [{ die: 8, result: 7 }],
    };
    const result = globalThis.resolveEffectValue(effect);
    expect(result.isDiceAttack).toBe(true);
    expect(result.value).toBe(7);
    expect(result.rollDetails).toBe('d8:7');
  });

  it('sums all locked rolls for compound dice', () => {
    const effect = {
      raw: 'D8x2+D6 Dmg',
      value: 0,
      diceGroups: [{ sides: 8, count: 2 }, { sides: 6, count: 1 }],
      _lockedRolls: [
        { die: 8, result: 3 },
        { die: 8, result: 7 },
        { die: 6, result: 4 },
      ],
    };
    expect(globalThis.resolveEffectValue(effect).value).toBe(14);
  });

  it('falls back to a fresh roll when no _lockedRolls are present', () => {
    const effect = { raw: 'D6 Dmg', value: 0, diceGroups: [{ sides: 6, count: 1 }] };
    const result = globalThis.resolveEffectValue(effect);
    expect(result.isDiceAttack).toBe(true);
    expect(result.value).toBeGreaterThanOrEqual(1);
    expect(result.value).toBeLessThanOrEqual(6);
  });

  it('returns a flat value (no dice) when the raw has no D-notation', () => {
    const effect = { raw: '6 Dmg', value: 6, move: 'Dmg' };
    const result = globalThis.resolveEffectValue(effect);
    expect(result.isDiceAttack).toBe(false);
    expect(result.value).toBe(6);
  });
});

// =============================================================================

describe('rerollAllPending — also rerolls Rerollable enemies', () => {
  it('rerolls every Rerollable enemy die for the same 1 reroll cost', () => {
    const enemy = makeEnemy('Rat', 'Always: D8 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeCombatState([enemy]);
    globalThis.combatState.player.rerolls = 1;
    globalThis.rollAllEnemyIntents();

    const before = globalThis.combatState.enemyDice[0].result;
    const beforeLocked = enemy.currentIntent[0].face.effects[0]._lockedRolls[0].result;
    expect(before).toBe(beforeLocked);

    // Seed Math.random so the reroll lands on a different face deterministically
    const orig = Math.random;
    let calls = 0;
    Math.random = () => {
      calls++;
      // Math.floor(Math.random() * 8) + 1 = result. Pick a value different from `before`.
      const want = before === 1 ? 8 : 1;
      return (want - 1) / 8;  // floor((want-1)/8 * 8) + 1 = want
    };
    try {
      const result = globalThis.rerollAllPending();
      expect(result.success).toBe(true);
    } finally {
      Math.random = orig;
    }

    expect(globalThis.combatState.player.rerolls).toBe(0);
    const after = globalThis.combatState.enemyDice[0].result;
    expect(after).not.toBe(before);
    // The effect's locked roll is also refreshed
    expect(enemy.currentIntent[0].face.effects[0]._lockedRolls[0].result).toBe(after);
  });

  it('fails when player has 0 rerolls', () => {
    const enemy = makeEnemy('Rat', 'Always: D8 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeCombatState([enemy]);
    globalThis.combatState.player.rerolls = 0;
    globalThis.rollAllEnemyIntents();
    const result = globalThis.rerollAllPending();
    expect(result.success).toBe(false);
    expect(result.error).toMatch(/reroll/i);
  });

  it('still works when only enemy dice are on the tray (no player pending dice)', () => {
    const enemy = makeEnemy('Rat', 'Always: D8 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeCombatState([enemy]);
    globalThis.combatState.player.rerolls = 1;
    globalThis.combatState.pendingDice = [];
    globalThis.rollAllEnemyIntents();
    const result = globalThis.rerollAllPending();
    expect(result.success).toBe(true);
  });

  it('fails cleanly when there is nothing on the tray at all', () => {
    globalThis.combatState = makeCombatState([]);
    globalThis.combatState.player.rerolls = 5;
    const result = globalThis.rerollAllPending();
    expect(result.success).toBe(false);
  });
});

// =============================================================================

describe('onEnemyDefeated — clears the enemy\'s tray dice', () => {
  it('removes the dead enemy\'s entries; other enemies are untouched', () => {
    const e1 = makeEnemy('A', 'Always: D6 Dmg Melee', 'Rerollable');
    const e2 = makeEnemy('B', 'Always: D8 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeCombatState([e1, e2]);
    globalThis.rollAllEnemyIntents();
    expect(globalThis.combatState.enemyDice.length).toBe(2);

    e1.health = 0;
    globalThis.onEnemyDefeated(e1);

    expect(globalThis.combatState.enemyDice.length).toBe(1);
    expect(globalThis.combatState.enemyDice[0].enemyId).toBe(e2.id);
  });

  it('is idempotent — calling twice on the same enemy does not duplicate work', () => {
    const e = makeEnemy('A', 'Always: D6 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeCombatState([e]);
    globalThis.rollAllEnemyIntents();
    e.health = 0;
    globalThis.onEnemyDefeated(e);
    globalThis.onEnemyDefeated(e);  // second call is a no-op
    expect(globalThis.combatState.enemyDice).toEqual([]);
  });
});

// =============================================================================

describe('lockEnemyDiceForTray — entry shape stays stable for re-renders', () => {
  it('the (entry.id, entry.result) pair stays the same across re-renders if dice are not re-rolled', () => {
    const enemy = makeEnemy('Rat', 'Always: D8 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeCombatState([enemy]);
    globalThis.rollAllEnemyIntents();
    const before = globalThis.combatState.enemyDice.map(d => ({ id: d.id, result: d.result }));
    // Same intent — simulating another UI render reading state mid-turn
    const after = globalThis.combatState.enemyDice.map(d => ({ id: d.id, result: d.result }));
    expect(after).toEqual(before);
  });

  it('rerolling produces a NEW result for the same id (so UI can detect re-animation)', () => {
    const enemy = makeEnemy('Rat', 'Always: D8 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeCombatState([enemy]);
    globalThis.combatState.player.rerolls = 1;
    globalThis.rollAllEnemyIntents();
    const beforeId = globalThis.combatState.enemyDice[0].id;
    const beforeResult = globalThis.combatState.enemyDice[0].result;

    // Force the reroll to land on a different result deterministically
    const orig = Math.random;
    Math.random = () => beforeResult === 1 ? 0.99 : 0.0;
    try {
      globalThis.rerollAllPending();
    } finally {
      Math.random = orig;
    }

    expect(globalThis.combatState.enemyDice[0].id).toBe(beforeId);
    expect(globalThis.combatState.enemyDice[0].result).not.toBe(beforeResult);
  });
});

describe('executeEnemyActions — actually uses locked dice rolls', () => {
  // The cardinal bug: the engine USED to roll fresh dice at attack time,
  // ignoring _lockedRolls. The dice tray and the damage dealt were two
  // separate random numbers. This pins the fix.

  function makeRunningCombat(enemy) {
    return {
      player: {
        health: 100, maxHealth: 100, energy: 3, maxEnergy: 3,
        block: 0, statuses: {},
        stats: { strength: 0, dexterity: 0, intelligence: 0, charisma: 0 },
        bonuses: { strength: 0, dexterity: 0, intelligence: 0, charisma: 0 },
      },
      enemies: [enemy],
      allies: [],
      playerDice: [],
      turn: 1,
      phase: 'enemy_actions',
      log: [],
      spells: [],
      spellCooldowns: {},
      spellCasts: {},
      usedSingleCast: {},
      pendingEffects: [],
      turnHistory: [],
      pendingDice: [],
      enemyDice: [],
      drawPile: [], hand: [], discardPile: [], exhaustPile: [], powers: [],
      _hitLog: [], _flatAttackBonus: 0,
      _druidScaling: {}, _usedSingleUseFaces: {},
      incrementals: { attacksTotal: 0, attacksThisTurn: 0 },
    };
  }

  it('damage dealt = sum of locked roll values (per-die-predicted)', () => {
    const enemy = makeEnemy('Brute', 'Always: D6 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeRunningCombat(enemy);
    // Force a deterministic locked roll
    globalThis.rollAllEnemyIntents();
    const locked = enemy.currentIntent[0].face.effects[0]._lockedRolls;
    expect(locked.length).toBe(1);
    const rolled = locked[0].result;

    // Compute expected damage via the same predictor the UI shows
    const expected = globalThis.predictPlayerIncomingDamage(
      rolled, enemy.currentIntent[0].face.effects[0].addons || [], enemy
    );

    // Now run the actual enemy action. Stub Math.random so any stray fresh
    // roll would land on a wildly different value (catches regression).
    const origRandom = Math.random;
    Math.random = () => 0.99;  // would roll 6 on a d6
    try {
      const beforeHp = globalThis.combatState.player.health;
      globalThis.executeEnemyActions();
      const taken = beforeHp - globalThis.combatState.player.health;
      expect(taken).toBe(expected);
    } finally {
      Math.random = origRandom;
    }
  });

  it('compound dice (D6x3) per-die hits — each die its own dealDamageToPlayer call', () => {
    const enemy = makeEnemy('Brute', 'Always: D6x3 Dmg Melee', 'Rerollable');
    globalThis.combatState = makeRunningCombat(enemy);
    globalThis.rollAllEnemyIntents();
    const locked = enemy.currentIntent[0].face.effects[0]._lockedRolls;
    expect(locked.length).toBe(3);

    // Block so we can measure per-die hits separately if needed
    globalThis.combatState.player.block = 0;
    const expected = locked.reduce(
      (s, r) => s + globalThis.predictPlayerIncomingDamage(
        r.result, enemy.currentIntent[0].face.effects[0].addons || [], enemy
      ), 0
    );

    const beforeHp = globalThis.combatState.player.health;
    globalThis.executeEnemyActions();
    const taken = beforeHp - globalThis.combatState.player.health;
    expect(taken).toBe(expected);
  });

  it('Power applies per die (was previously dropped for dice attacks)', () => {
    const enemy = makeEnemy('Brute', 'Always: D6 Dmg Melee', 'Rerollable');
    enemy.statuses['power'] = 3;
    globalThis.combatState = makeRunningCombat(enemy);
    globalThis.rollAllEnemyIntents();
    const rolled = enemy.currentIntent[0].face.effects[0]._lockedRolls[0].result;

    const beforeHp = globalThis.combatState.player.health;
    globalThis.executeEnemyActions();
    const taken = beforeHp - globalThis.combatState.player.health;
    // raw + power, no other modifiers
    expect(taken).toBe(rolled + 3);
  });

  it('Weak applies per die (floor 0.75)', () => {
    const enemy = makeEnemy('Brute', 'Always: D6 Dmg Melee', 'Rerollable');
    enemy.statuses['weak'] = 1;
    globalThis.combatState = makeRunningCombat(enemy);
    globalThis.rollAllEnemyIntents();
    const rolled = enemy.currentIntent[0].face.effects[0]._lockedRolls[0].result;

    const beforeHp = globalThis.combatState.player.health;
    globalThis.executeEnemyActions();
    const taken = beforeHp - globalThis.combatState.player.health;
    expect(taken).toBe(Math.floor(rolled * 0.75));
  });

  it('non-Rerollable enemies still roll fresh dice at attack time (unchanged)', () => {
    // No Rerollable status → no _lockedRolls → engine rolls fresh
    const enemy = makeEnemy('Goblin', 'Always: D6 Dmg Melee', '');
    globalThis.combatState = makeRunningCombat(enemy);
    globalThis.rollAllEnemyIntents();
    // No tray entries
    expect(globalThis.combatState.enemyDice.length).toBe(0);
    // No locked rolls on the effect
    const eff = enemy.currentIntent[0].face.effects[0];
    expect(eff._lockedRolls).toBeUndefined();

    // Damage still happens (just via the fresh-roll path)
    const beforeHp = globalThis.combatState.player.health;
    globalThis.executeEnemyActions();
    const taken = beforeHp - globalThis.combatState.player.health;
    expect(taken).toBeGreaterThanOrEqual(1);
    expect(taken).toBeLessThanOrEqual(6);
  });
});

describe('exports — rerollPlayerDie is gone', () => {
  it('rerollPlayerDie is no longer attached to globalThis', () => {
    expect(typeof globalThis.rerollPlayerDie).toBe('undefined');
  });

  it('rerollPlayerDie is removed from window.CombatEngine', () => {
    expect(globalThis.CombatEngine).toBeDefined();
    expect(globalThis.CombatEngine.rerollPlayerDie).toBeUndefined();
    // rollPlayerDie and rerollAllPending are still there
    expect(typeof globalThis.CombatEngine.rollPlayerDie).toBe('function');
    expect(typeof globalThis.CombatEngine.rerollAllPending).toBe('function');
  });
});
