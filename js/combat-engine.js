/**
 * Combat Engine - New Dice-Based Combat System
 * Handles the Slice & Dice inspired combat with:
 * - Character/Weapon/Ally dice pools
 * - Moves (Dmg, Block, Heal, etc.) with stat scaling
 * - Addons (Cantrip, Cleave, Wide, etc.)
 * - Status effects (Burn, Poison, Dodge, etc.)
 * - Spell system with keywords
 * - Energy and Mana resources
 */

// ============== COMBAT STATE ==============

var combatState = null;

/**
 * Initialize a new combat encounter
 * @param {Array} enemies - Array of enemy data from ENEMIES_DATA
 * @param {Object} characterData - Character data including dice
 * @param {Object} weaponData - Equipped weapon data (optional)
 * @param {Array} allies - Array of ally data (optional)
 * @returns {Object} Combat state
 */
function initCombat(enemies, characterData, weaponData = null, allies = []) {
  // Get player stats
  const playerStats = {
    strength: typeof getEffectiveStat === 'function' ? getEffectiveStat('strength') : (window.strength || 0),
    dexterity: typeof getEffectiveStat === 'function' ? getEffectiveStat('dexterity') : (window.dexterity || 0),
    intelligence: typeof getEffectiveStat === 'function' ? getEffectiveStat('intelligence') : (window.intelligence || 0),
    charisma: typeof getEffectiveStat === 'function' ? getEffectiveStat('charisma') : (window.charisma || 0)
  };

  // Calculate stat bonuses (every 3 = +1) - ensure valid numbers
  const statBonuses = {
    strength: Math.floor((playerStats.strength || 0) / 3) || 0,
    dexterity: Math.floor((playerStats.dexterity || 0) / 3) || 0,
    intelligence: Math.floor((playerStats.intelligence || 0) / 3) || 0,
    charisma: Math.floor((playerStats.charisma || 0) / 3) || 0
  };
  // Persistence uses a 5:1 ratio (every 5 Charisma = 1 Persistence)
  const persistenceBonusInit = Math.floor((playerStats.charisma || 0) / 5);

  // Create player state - ensure health values are valid numbers
  const playerHealth = (typeof window.health === 'number' && !isNaN(window.health)) ? window.health : 10;
  const playerMaxHealth = (typeof window.maxHealth === 'number' && !isNaN(window.maxHealth)) ? window.maxHealth : 10;

  const player = {
    health: playerHealth,
    maxHealth: playerMaxHealth,
    energy: (typeof gameState !== 'undefined' && gameState.maxEnergy) || characterData.energy || 2,
    maxEnergy: (typeof gameState !== 'undefined' && gameState.maxEnergy) || characterData.energy || 2,
    mana: 0,
    maxMana: characterData.mana || 0,
    stats: playerStats,
    bonuses: statBonuses,
    block: 0,
    statuses: {},
    rerolls: window.reroll || 0,
    dash: window.dash || 0
  };

  // Translate stat-derived bonuses into starting combat statuses so that card effects
  // (which read statuses['power'] / statuses['defense']) benefit from the player's stats.
  // _statPower tracks the str-derived portion so finesse weapons can subtract it back out.
  if (statBonuses.strength > 0) {
    player.statuses['power'] = statBonuses.strength;
    player._statPower = statBonuses.strength;
  }
  if (statBonuses.dexterity > 0) {
    player.statuses['defense'] = statBonuses.dexterity;
  }
  if (statBonuses.intelligence > 0) {
    player.statuses['arcane'] = statBonuses.intelligence;
  }
  if (persistenceBonusInit > 0) {
    player.statuses['persistence'] = persistenceBonusInit;
  }

  // Apply pending combat statuses from pre-combat events (e.g. Fear, Blind)
  if (typeof gameState !== 'undefined' && Array.isArray(gameState.pendingCombatStatuses)) {
    gameState.pendingCombatStatuses.forEach(({ status, stacks }) => {
      player.statuses[status] = (player.statuses[status] || 0) + (stacks || 1);
    });
    gameState.pendingCombatStatuses = [];
  }

  // Create dice pool for player
  const playerDice = [];

  // Add character die
  if (characterData.dice) {
    playerDice.push({
      id: 'character',
      name: characterData.name,
      source: 'character',
      faces: characterData.dice,
      currentFace: null,
      isRolled: false,
      isConfirmed: false,
      isExhausted: false,
      energyCost: 1
    });
  }

  // Add weapon die if equipped
  if (weaponData && weaponData.dice) {
    playerDice.push({
      id: 'weapon',
      name: weaponData.name,
      source: 'weapon',
      faces: weaponData.dice,
      currentFace: null,
      isRolled: false,
      isConfirmed: false,
      isExhausted: false,
      energyCost: 1,
      tags: weaponData.tags || []
    });
  }

  // Add ally dice
  allies.forEach((ally, index) => {
    if (ally.dice) {
      playerDice.push({
        id: `ally_${index}`,
        name: ally.name,
        source: 'ally',
        allyData: ally,
        faces: ally.dice,
        currentFace: null,
        isRolled: false,
        isConfirmed: false,
        isExhausted: false,
        energyCost: 1
      });
    }
  });

  // Create enemy states
  const enemyStates = enemies.map((enemy, index) => {
    // Parse starting abilities from enemy.ability
    const startingStatuses = parseStartingAbilities(enemy.ability);

    // Randomize HP from min-max range
    let hp;
    if (enemy.hpMin !== undefined && enemy.hpMax !== undefined) {
      hp = Math.floor(Math.random() * (enemy.hpMax - enemy.hpMin + 1)) + enemy.hpMin;
    } else {
      hp = enemy.hp || 10;
    }

    // Determine intent pattern type from pattern string
    // "Always: ..." → random each turn
    // "Turn 1: ... | Turn 2: ... | Next: ..." → ordered turns
    const patternStr = enemy.pattern || '';
    const isOrderedPattern = /Turn \d+:/i.test(patternStr);
    const parsedPattern = isOrderedPattern ? parseOrderedPattern(patternStr) : null;

    const enemyState = {
      id: `enemy_${index}`,
      name: enemy.name,
      type: enemy.type,
      difficulty: enemy.difficulty,
      weight: enemy.weight,
      health: hp,
      maxHealth: hp,
      block: 0,
      statuses: startingStatuses,
      ability: enemy.ability,
      pattern: patternStr,
      patternType: isOrderedPattern ? 'ordered' : 'random',
      patternTurns: parsedPattern,  // Array of turn entries for ordered patterns
      patternTurnIndex: 0,          // Current position in ordered pattern
      game: enemy.game,
      location: enemy.location,
      dice: enemy.dice,
      currentIntent: null,
      imageUrl: enemy.imageUrl,
      position: index,              // Position for Cleave targeting
      staggerThreshold: parseStaggerThreshold(enemy.ability),
      rolledFaces: new Set(),       // For Forgetful tracking
      curlUpTriggeredThisTurn: false,
      splitAbility: parseSplitAbility(enemy.ability)
    };
    resolveDeterminedValues(enemyState);
    return enemyState;
  });

  // Create ally states (for HP tracking)
  const allyStates = allies.map((ally, index) => ({
    id: `ally_${index}`,
    name: ally.name,
    health: ally.hp,
    maxHealth: ally.hp,
    block: 0,
    statuses: {},
    ability: ally.ability,
    isAlive: true,
    position: index,
    imageUrl: ally.imageUrl
  }));

  // Initialize combat state
  combatState = {
    player: player,
    enemies: enemyStates,
    allies: allyStates,
    playerDice: playerDice,
    turn: 1,
    phase: 'enemy_intent', // 'enemy_intent', 'player_status', 'player_action', 'end_turn', 'victory', 'defeat'
    log: [],
    spells: [], // Player's available spells
    spellCooldowns: {}, // Track spell cooldowns
    spellCasts: {}, // Track how many times each spell was cast (for Channel/Deplete)
    usedSingleCast: {}, // Track SingleCast spells used this combat
    pendingEffects: [], // Effects waiting to be resolved
    turnHistory: [],
    pendingDice: [],      // Rolled dice faces waiting to be used
    _druidScaling: {},    // {cardName_faceIndex: bonusValue} — Druid scaling per face
    _usedSingleUseFaces: {} // {cardName_faceIndex: true} — Single Use faces consumed this combat
  };

  // Load player's spells from gameState (persisted across combats)
  if (typeof gameState !== 'undefined' && Array.isArray(gameState.spells) && gameState.spells.length > 0) {
    combatState.spells = [...gameState.spells];
  } else if (typeof window.playerSpells !== 'undefined') {
    combatState.spells = [...window.playerSpells];
  }

  // Initialize card deck system
  combatState.drawPile = [];
  combatState.hand = [];
  combatState.discardPile = [];
  combatState.exhaustPile = [];
  combatState.powers = [];
  combatState.selectedCardIndex = null;
  combatState.reshuffleQueued = false;
  combatState.lastPlayedCard = null;
  combatState._scalingCounters = {}; // Tracks per-combat scaling bonuses (e.g. Claw damage bonus)
  combatState._discardedThisTurn = false; // Tracks if player discarded a card this turn (Sneaky Strike)
  combatState._discardsThisTurn = 0;      // Count of cards discarded this turn (Eviscerate cost)
  combatState._playerHealthLossTimes = 0; // Times player took actual HP damage this combat (Masterful Stab)
  // Flat attack bonus from items (Focus Crystal, Beefy Ring, etc.) — added per-hit to attack cards
  combatState._hitLog = []; // Per-play hit records for multi-hit visual playback
  combatState._flatAttackBonus = 0;
  if (typeof recalculateScalablePassives === 'function') {
    try {
      const passiveBonuses = recalculateScalablePassives();
      combatState._flatAttackBonus = passiveBonuses.attack || 0;
    } catch (e) {}
  }
  initCombatDeck(characterData);

  addLog('Combat started!', 'info');

  // Log stat-derived power/defense/arcane/persistence applied at combat start
  if (statBonuses.strength > 0) {
    addLog(`Power +${statBonuses.strength} (${playerStats.strength} Strength)`, 'success');
  }
  if (statBonuses.dexterity > 0) {
    addLog(`Defense +${statBonuses.dexterity} (${playerStats.dexterity} Dexterity)`, 'success');
  }
  if (statBonuses.intelligence > 0) {
    addLog(`Arcane +${statBonuses.intelligence} (${playerStats.intelligence} Intelligence)`, 'success');
  }
  if (persistenceBonusInit > 0) {
    addLog(`Persistence +${persistenceBonusInit} (${playerStats.charisma} Charisma)`, 'success');
  }

  // Check for Philosopher's Stone - enemies start with Power
  if (typeof inventory !== 'undefined') {
    const philosopherStoneCount = inventory.filter(i => i.name === "Philosopher's Stone").length;
    if (philosopherStoneCount > 0) {
      // Each enemy gets 1 Power (does not stack with multiple stones)
      combatState.enemies.forEach(enemy => {
        enemy.statuses.power = (enemy.statuses.power || 0) + 1;
      });
      addLog("Philosopher's Stone: All enemies start with 1 Power", 'warning');
    }

    // Trigger Blood Vial onCombatStart effect
    const bloodVialEffect = ITEM_EFFECTS && ITEM_EFFECTS['Blood Vial'];
    if (bloodVialEffect && bloodVialEffect.onCombatStart) {
      const hasBloodVial = inventory.some(i => i.name === 'Blood Vial');
      if (hasBloodVial) {
        bloodVialEffect.onCombatStart();
      }
    }

    // Garlic: apply +1 Brace per Garlic in inventory
    const garlicCount = inventory.filter(i => i.name === 'Garlic').reduce((n, i) => n + (i.quantity || 1), 0);
    if (garlicCount > 0) {
      combatState.player.statuses['brace'] = (combatState.player.statuses['brace'] || 0) + garlicCount;
      addLog(`Garlic: +${garlicCount} Brace`, 'info');
    }

    // Leech Brood: inflict +1 Leeches to all enemies at start of conflict
    // If player is above 50% health, lose 10 health
    if (inventory.some(i => i.name === 'Leech Brood')) {
      combatState.enemies.forEach(enemy => {
        enemy.statuses['leeches'] = (enemy.statuses['leeches'] || 0) + 1;
        enemy.statuses['leeches_owner'] = 'player';
      });
      addLog('Leech Brood: +1 Leeches on all enemies', 'warning');
      if (combatState.player.health > combatState.player.maxHealth * 0.5) {
        combatState.player.health = Math.max(1, combatState.player.health - 10);
        window.health = combatState.player.health;
        addLog('Leech Brood: you were above 50% health — lost 10 HP!', 'danger');
      }
    }

    // Raven Feather: inflict Soul Link on 2 random enemies at start of conflict
    if (inventory.some(i => i.name === 'Raven Feather')) {
      const living = combatState.enemies.filter(e => e.health > 0);
      const targets = living.sort(() => Math.random() - 0.5).slice(0, 2);
      targets.forEach(e => {
        e.statuses['soul_link'] = 1;
      });
      if (targets.length > 0) {
        addLog(`Raven Feather: Soul Link on ${targets.map(e => e.name).join(', ')}`, 'warning');
      }
    }

    // Horn Cleat: handled in processPlayerStartOfTurn (start of turn 2 → +14 Block)
    if (inventory.some(i => i.name === 'Horn Cleat')) {
      combatState._hornCleatPending = true;
    }

    // Bronze Scales: +3 Thorns at start of combat
    const bronzeScalesCount = inventory.filter(i => i.name === 'Bronze Scales').reduce((n, i) => n + (i.quantity || 1), 0);
    if (bronzeScalesCount > 0) {
      combatState.player.statuses['thorns'] = (combatState.player.statuses['thorns'] || 0) + 3 * bronzeScalesCount;
      addLog(`Bronze Scales: +${3 * bronzeScalesCount} Thorns`, 'info');
    }

    // Du-Vu Doll: at start of combat, gain X Power where X = curse count
    const duVuCount = inventory.filter(i => i.name === 'Du-Vu Doll').reduce((n, i) => n + (i.quantity || 1), 0);
    if (duVuCount > 0) {
      const curseCount = (typeof gameState !== 'undefined' && gameState.activeCurses) ? gameState.activeCurses.length : 0;
      if (curseCount > 0) {
        const powerGain = curseCount * duVuCount;
        combatState.player.statuses['power'] = (combatState.player.statuses['power'] || 0) + powerGain;
        addLog(`Du-Vu Doll: +${powerGain} Power!`, 'info');
      }
    }

    // Thread and Needle: +4 Plated Armor at start of combat
    if (inventory.some(i => i.name === 'Thread and Needle')) {
      combatState.player.statuses['plated_armor'] = (combatState.player.statuses['plated_armor'] || 0) + 4;
      addLog('Thread and Needle: +4 Plated Armor', 'info');
    }

    // Pummarola: +1 Regeneration at start of combat (per copy)
    const pummarolaCount = inventory.filter(i => i.name === 'Pummarola').reduce((n, i) => n + (i.quantity || 1), 0);
    if (pummarolaCount > 0) {
      combatState.player.statuses['regeneration'] = (combatState.player.statuses['regeneration'] || 0) + pummarolaCount;
      addLog(`Pummarola: +${pummarolaCount} Regeneration`, 'info');
    }

    // Bear Trap Mask: +4 Shield and +1 Bleed Thorns at combat start
    if (inventory.some(i => i.name === 'Bear Trap Mask')) {
      combatState.player.block = (combatState.player.block || 0) + 4;
      combatState.player.statuses['bleed_thorns'] = (combatState.player.statuses['bleed_thorns'] || 0) + 1;
      addLog('Bear Trap Mask: +4 Shield and +1 Bleed Thorns', 'info');
    }

    // Broken Window: player gains +3 Bleed Thorns and +1 Bleed at combat start
    if (inventory.some(i => i.name === 'Broken Window')) {
      combatState.player.statuses['bleed_thorns'] = (combatState.player.statuses['bleed_thorns'] || 0) + 3;
      combatState.player.statuses['bleed'] = (combatState.player.statuses['bleed'] || 0) + 1;
      addLog('Broken Window: +3 Bleed Thorns and +1 Bleed', 'warning');
    }

    // Empty Syringe: passive flag — tracked in applyStatus
    combatState._emptySyringeActive = inventory.some(i => i.name === 'Empty Syringe');
  }

  // Initialize incremental item counters — attacksTotal persists across combats via gameState.runAttacks
  const savedRunAttacks = (typeof gameState !== 'undefined' && gameState.runAttacks) ? gameState.runAttacks : 0;
  combatState.incrementals = {
    attacksTotal: savedRunAttacks,  // cumulative attacks this run (Pen Nib, Nunchaku)
    attacksThisTurn: 0,             // attacks played this turn (Ornamental Fan, Shuriken)
  };

  // Curse of Weakness: start combat with 3 Weak
  if (typeof CurseManager !== 'undefined') {
    const weaknessCurses = CurseManager.findByType('weakness');
    weaknessCurses.forEach(curse => {
      combatState.player.statuses['weak'] = (combatState.player.statuses['weak'] || 0) + 3;
      addLog(`Curse of Weakness: started with 3 Weak`, 'danger');
    });

    // Curse of Obstruction: all enemies gain Plated Armor at start of combat
    const obstructionCurses = CurseManager.findByType('obstruction');
    obstructionCurses.forEach(curse => {
      const armorAmounts = { Low: 3, Medium: 5, High: 7 };
      const armorAmt = armorAmounts[curse.power] || 3;
      combatState.enemies.forEach(e => {
        e.statuses['plated_armor'] = (e.statuses['plated_armor'] || 0) + armorAmt;
      });
      addLog(`Curse of Obstruction: all enemies gained +${armorAmounts[curse.power] || 3} Plated Armor`, 'danger');
    });
  }

  // Roll enemy intents
  rollAllEnemyIntents();

  // Transition to player status phase
  combatState.phase = 'player_status';
  processPlayerStartOfTurn();

  // Items that grant block or draw at combat start must be applied AFTER processPlayerStartOfTurn
  // clears the initial block and draws the starting hand.
  if (typeof inventory !== 'undefined') {
    // Anchor: +10 Block at start of combat (applied after start-of-turn block clear)
    const anchorCount = inventory.filter(i => i.name === 'Anchor').reduce((n, i) => n + (i.quantity || 1), 0);
    if (anchorCount > 0) {
      addBlock(combatState.player, 10 * anchorCount);
      addLog(`Anchor: +${10 * anchorCount} Block!`, 'info');
    }

    // Holy Mantle: +1 Holy Shield at start of combat
    const holyMantleCount = inventory.filter(i => i.name === 'Holy Mantle').reduce((n, i) => n + (i.quantity || 1), 0);
    if (holyMantleCount > 0) {
      combatState.player.statuses['buffer'] = (combatState.player.statuses['buffer'] || 0) + holyMantleCount;
      addLog(`Holy Mantle: +${holyMantleCount} Buffer!`, 'success');
    }

    // Ring of the Snake: draw 2 extra cards at combat start (applied after normal hand draw)
    const snakeEffect = typeof ITEM_EFFECTS !== 'undefined' && ITEM_EFFECTS['Ring of the Snake'];
    if (snakeEffect && snakeEffect.onCombatStart && inventory.some(i => i.name === 'Ring of the Snake')) {
      snakeEffect.onCombatStart();
    }
  }

  return combatState;
}

/**
 * Parse starting abilities from enemy ability string
 * @param {string} abilityStr - e.g., "Starts with Forgetful, Barricade"
 * @returns {Object} Status object
 */
function parseStartingAbilities(abilityStr) {
  const statuses = {};
  if (!abilityStr) return statuses;
  if (abilityStr.trim().toUpperCase() === 'N/A') return statuses;

  // Split by '/' to get individual clauses; then split non-"When" clauses by ',' too.
  // "When Defeated, ..." style clauses are left intact then skipped.
  const rawParts = [];
  for (const slashPart of abilityStr.split('/')) {
    const trimmed = slashPart.trim();
    if (/^when\b/i.test(trimmed)) {
      rawParts.push(trimmed); // keep "When ..." intact so it isn't garbled by comma split
    } else {
      for (const commaPart of trimmed.split(',')) {
        rawParts.push(commaPart.trim());
      }
    }
  }

  for (const seg of rawParts) {
    if (!seg) continue;
    // Skip defeat-trigger and "When another …" clauses entirely
    if (/^when\b/i.test(seg) || /defeat/i.test(seg)) continue;
    // Skip probability-prefixed segments that are death-trigger alternatives
    // e.g. "40% Spawn Gusher" is the tail of "When Defeated, 60% X / 40% Y"
    if (/^\d+%\s+/i.test(seg)) continue;

    // "Curl Up Determined(X-Y)" — roll block amount once at combat start
    const curlUpDetMatch = seg.match(/^Curl\s+Up\s+Determined\((\d+)-(\d+)\)$/i);
    if (curlUpDetMatch) {
      const lo = parseInt(curlUpDetMatch[1]), hi = parseInt(curlUpDetMatch[2]);
      statuses['curl_up'] = Math.floor(Math.random() * (hi - lo + 1)) + lo;
      continue;
    }

    // "Curl Up N" — fixed block amount
    const curlUpFixedMatch = seg.match(/^Curl\s+Up\s+(\d+)$/i);
    if (curlUpFixedMatch) { statuses['curl_up'] = parseInt(curlUpFixedMatch[1]); continue; }

    // Plain "Curl Up" — treat as curl_up flag (will need curlUpValue from elsewhere)
    if (/^Curl\s+Up$/i.test(seg)) { statuses['curl_up'] = 1; continue; }

    // Skip "Split N Name" — handled separately via parseSplitAbility
    if (/^Split\s+\d+/i.test(seg)) continue;

    // Fading N
    const fadingMatch = seg.match(/^Fading\s+(\d+)$/i);
    if (fadingMatch) { statuses['fading'] = parseInt(fadingMatch[1]); continue; }

    // Multi Attack N
    const multiMatch = seg.match(/^Multi\s+Attack\s+(\d+)$/i);
    if (multiMatch) { statuses['multi_attack'] = parseInt(multiMatch[1]); continue; }

    // Stagger N% — stored via parseStaggerThreshold; no status entry needed
    if (/^Stagger\s+\d+%?$/i.test(seg)) continue;

    // Immune to X  →  immune_x
    const immuneMatch = seg.match(/^Immune\s+to\s+(.+)$/i);
    if (immuneMatch) {
      statuses['immune_' + immuneMatch[1].toLowerCase().replace(/\s+/g, '_')] = 1;
      continue;
    }

    // N StatusName  (e.g., "3 Thorns")
    const numNameMatch = seg.match(/^(\d+)\s+(\w[\w\s]*)$/);
    if (numNameMatch) {
      const key = numNameMatch[2].trim().toLowerCase().replace(/\s+/g, '_');
      statuses[key] = parseInt(numNameMatch[1]);
      continue;
    }

    // Named ability → snake_case key, value 1
    // (Pigment Rich, Rerollable, Rust, Formless, Shifting, Barricade, Forgetful, etc.)
    const key = seg.trim().toLowerCase().replace(/\s+/g, '_');
    if (key) statuses[key] = 1;
  }

  return statuses;
}

/**
 * Parse the stagger threshold (as a fraction 0-1) from an ability string.
 * "Stagger 33%" → 0.33.  Returns null if no stagger ability.
 */
function parseStaggerThreshold(abilityStr) {
  if (!abilityStr) return null;
  const m = abilityStr.match(/Stagger\s+(\d+(?:\.\d+)?)%/i);
  return m ? parseFloat(m[1]) / 100 : null;
}

/**
 * Pre-roll all Determined(X-Y) values from an enemy's pattern string.
 * Each unique "X-Y" range gets one fixed value for the whole combat.
 * @param {Object} enemy - Enemy state object (must have .pattern)
 */
function resolveDeterminedValues(enemy) {
  enemy.determinedValues = {};
  const regex = /Determined\((\d+)-(\d+)\)/gi;
  let m;
  while ((m = regex.exec(enemy.pattern || '')) !== null) {
    const key = `${m[1]}-${m[2]}`;
    if (!(key in enemy.determinedValues)) {
      const lo = parseInt(m[1]), hi = parseInt(m[2]);
      enemy.determinedValues[key] = Math.floor(Math.random() * (hi - lo + 1)) + lo;
    }
  }
}

/**
 * Replace Determined(X-Y) tokens in a description with the enemy's pre-rolled values.
 * @param {string} desc
 * @param {Object} enemy
 * @returns {string}
 */
function applyDetermined(desc, enemy) {
  if (!desc || !enemy.determinedValues) return desc;
  return desc.replace(/Determined\((\d+)-(\d+)\)/gi, (match, lo, hi) => {
    const key = `${lo}-${hi}`;
    if (enemy.determinedValues[key] !== undefined) return String(enemy.determinedValues[key]);
    // Safety fallback: roll fresh if somehow not pre-rolled
    const val = Math.floor(Math.random() * (parseInt(hi) - parseInt(lo) + 1)) + parseInt(lo);
    enemy.determinedValues[key] = val;
    return String(val);
  });
}

/**
 * Parse split ability from ability string.
 * "Split 2 Acid Slime (M)" → { count: 2, spawnName: "Acid Slime (M)" }
 * Returns null if no split ability.
 */
function parseSplitAbility(abilityStr) {
  if (!abilityStr) return null;
  const m = abilityStr.match(/\bSplit\s+(\d+)\s+(.+)/i);
  if (!m) return null;
  return { count: parseInt(m[1]), spawnName: m[2].trim(), triggered: false, splitting: false };
}

/**
 * Parse an ordered pattern string into an array of turn entries.
 * Pattern format: "Turn 1: <desc> | Turn 2: <desc> | Next: Repeat"
 * or              "Turn 1: <desc> | Next: <desc>"
 * Returns an array of { label, description } objects.
 * The last entry with label "Next" defines what to loop from.
 */
function parseOrderedPattern(patternStr) {
  const turns = [];
  const parts = patternStr.split('|').map(p => p.trim());
  for (const part of parts) {
    const colonIdx = part.indexOf(':');
    if (colonIdx === -1) continue;
    const label = part.slice(0, colonIdx).trim();
    const description = part.slice(colonIdx + 1).trim();
    turns.push({ label, description });
  }
  return turns;
}

/**
 * Parse an ordered-pattern description string into an effects array that
 * executeEnemyActions can iterate over.
 *
 * Handles probability splits: "50% 10 Dmg Ranged / 50% 7 Dmg Melee 2 Vulnerable"
 * Handles simple sequences:   "10 Dmg Ranged"  /  "6 Dmg Ranged 1 Burn"
 * Handles no-ops:             "Unknown Intent (\"Charging\")"
 */
const PATTERN_ADDONS   = new Set(['ranged','melee','pierce','self','engage','trap','aoe','splash','overload','overloadexceptleft','overloadexceptright','cleave']);
const PATTERN_STATUSES = new Set([
  'burn','poison','weak','vulnerable','stun','oiled','dodge','power','frail','enfeebled','confused',
  'barricade','fading','thorns','shifting','formless','ritual','ruptured','bleed','slow','silence',
  'arcane','persistence','flame_barrier','bleed_thorns','wet',
]);
// Statuses that do not stack — applying again just sets to 1
const NON_STACKABLE_STATUSES = new Set(['stun', 'dodge', 'silence', 'confused']);

/**
 * Apply a status to a unit, respecting non-stackable caps.
 */
// Add a random pigment/status card to the player's combat hand
function addPigmentCardToHand() {
  if (!combatState) return;
  // Only pick cards explicitly tagged as pigments, never status cards like Slimed
  const pool = (typeof CARDS_DATA !== 'undefined' ? CARDS_DATA : [])
    .filter(c => c.isStatusCard && c.tags && c.tags.includes('pigment'));
  if (pool.length === 0) return;
  const card = { ...pool[Math.floor(Math.random() * pool.length)] };
  if (!combatState.hand) combatState.hand = [];
  combatState.hand.push(card);
  addLog('A pigment card was added to your hand!', 'success');
  if (typeof window.updateCombatDisplay === 'function') window.updateCombatDisplay();
}

function applyStatus(unit, statusName, amount) {
  if (!unit || !unit.statuses) return;
  const key = statusName.toLowerCase();

  // Water-Fire interaction: applying Burn to a Wet target reduces Wet by 1 instead
  if (key === 'burn' && unit.statuses['wet'] && unit.statuses['wet'] > 0) {
    unit.statuses['wet'] = Math.max(0, unit.statuses['wet'] - 1);
    if (unit.statuses['wet'] <= 0) delete unit.statuses['wet'];
    addLog(`Burn blocked by Wet on ${unit.name || 'target'}! Wet reduced.`, 'info');
    return;
  }

  if (NON_STACKABLE_STATUSES.has(key)) {
    unit.statuses[key] = 1;
  } else {
    unit.statuses[key] = (unit.statuses[key] || 0) + amount;
  }

  // Empty Syringe: inflicting Bleed or Poison on an enemy adds +1 extra
  if (combatState && combatState._emptySyringeActive && unit !== combatState.player
      && (key === 'bleed' || key === 'poison')) {
    unit.statuses[key] = (unit.statuses[key] || 0) + 1;
    addLog(`Empty Syringe: +1 extra ${key} on ${unit.name || 'enemy'}!`, 'info');
  }
}

/**
 * Evaluate turn-scaling formulas in a pattern description.
 * Replaces "N + (Turn Number - A x B)" with the computed value for the current turn.
 * Example: "30 + (Turn Number - 1 x 10)" on turn 3 → "50"
 */
function evaluateScalingFormulas(desc) {
  return desc.replace(
    /(\d+)\s*\+\s*\(Turn\s+Number\s*-\s*(\d+)\s*[xX×]\s*(\d+)\)/gi,
    (_, base, sub, mult) => {
      const turn = (combatState && combatState.turn) || 1;
      return String(parseInt(base) + (turn - parseInt(sub)) * parseInt(mult));
    }
  );
}

function parsePatternDescToEffects(desc) {
  if (!desc) return { effects: [], text: '' };

  // Evaluate turn-scaling formulas (e.g. Transient) before any other parsing
  desc = evaluateScalingFormulas(desc);

  // Probability split FIRST: "50% desc1 / 50% desc2"
  // Must run before unknown-intent check so each branch is resolved independently.
  // e.g. "75% Unknown Intent ("Wandering") / 25% 6 Dmg Ranged" rolls and picks ONE.
  if (desc.includes('%') && desc.includes('/')) {
    const options = desc.split('/').map(s => s.trim());
    const weighted = [];
    for (const opt of options) {
      const m = opt.match(/^(\d+(?:\.\d+)?)%\s*(.*)/);
      if (m) weighted.push({ weight: parseFloat(m[1]), text: m[2].trim() });
    }
    if (weighted.length > 0) {
      const total = weighted.reduce((s, o) => s + o.weight, 0);
      let roll = Math.random() * total;
      for (const o of weighted) {
        roll -= o.weight;
        if (roll <= 0) return parsePatternDescToEffects(o.text);
      }
      const last = weighted[weighted.length - 1];
      return parsePatternDescToEffects(last.text);
    }
  }

  // Unknown intent check AFTER probability split so each branch resolves independently.
  // Extract the label from "Unknown Intent ("Label")" to show just the label.
  if (/unknown intent/i.test(desc)) {
    const labelMatch = desc.match(/unknown intent\s*\(\s*"?([^")]+)"?\s*\)/i);
    const text = labelMatch ? labelMatch[1].trim() : desc;
    return { effects: [], text };
  }

  // "Add N random Pigment ... to (your) deck/hand"
  if (/\badd \d+ random pigment/i.test(desc)) {
    return { effects: [{ raw: desc, value: 1, move: 'AddPigment', addons: [], target: null }], text: desc };
  }

  // "Consume N random Pigment ... for X Power, Y Block"
  if (/\bconsume \d+ random pigment/i.test(desc)) {
    const m = desc.match(/for\s+(\d+)\s+Power,?\s*(\d+)\s+Block/i);
    return { effects: [{ raw: desc, value: 1, move: 'ConsumePigment', addons: [],
              power: m ? parseInt(m[1]) : 0, block: m ? parseInt(m[2]) : 0 }], text: desc };
  }

  return { effects: parseSimplePatternDesc(desc), text: desc };
}

function parseSimplePatternDesc(text) {
  const effects = [];
  // Strip trailing commas from each token so "Ranged," is treated the same as "Ranged"
  const tokens  = text.trim().split(/\s+/).map(t => t.replace(/,+$/, ''));
  let i = 0;
  while (i < tokens.length) {
    // NxM notation: "5x4 Dmg Ranged" → 5 damage, 4 times
    const nxmMatch = tokens[i].match(/^(\d+)[xX](\d+)$/);
    if (nxmMatch) {
      const dmgVal = parseInt(nxmMatch[1]);
      const times  = parseInt(nxmMatch[2]);
      i++;
      if (i < tokens.length && tokens[i].toLowerCase() === 'dmg') {
        i++;
        const addons = [];
        while (i < tokens.length && PATTERN_ADDONS.has(tokens[i].toLowerCase())) {
          addons.push(tokens[i++]);
        }
        effects.push({ raw: `${dmgVal}x${times} Dmg`, value: dmgVal, move: 'Dmg', addons, times });
      }
      continue;
    }

    // Dice notation: "D8 Dmg", "D6x3 Dmg", "D8x2+D10x3 Dmg"
    // D<sides>, D<sides>x<count>, or compound D<s1>x<c1>+D<s2>x<c2>
    if (/^D\d+/i.test(tokens[i])) {
      const rawDice = tokens[i]; i++;
      if (i < tokens.length && tokens[i].toLowerCase() === 'dmg') {
        i++;
        const addons = [];
        while (i < tokens.length && PATTERN_ADDONS.has(tokens[i].toLowerCase())) {
          addons.push(tokens[i++]);
        }
        // Parse each dice group from compound notation (e.g. "D8x2+D10x3" → two groups)
        const diceGroups = [];
        for (const part of rawDice.split('+')) {
          const m = part.match(/^D(\d+)(?:[xX](\d+))?$/i);
          if (m) diceGroups.push({ sides: parseInt(m[1]), count: m[2] ? parseInt(m[2]) : 1 });
        }
        effects.push({ raw: `${rawDice} Dmg`, value: 0, move: 'Dmg', addons, diceGroups });
      }
      continue;
    }

    // "Lose All <Status>" or "Lose <N> <Status>"
    if (tokens[i].toLowerCase() === 'lose') {
      i++;
      if (i >= tokens.length) break;
      let loseAll = false;
      let loseCount = 0;
      if (tokens[i].toLowerCase() === 'all') {
        loseAll = true;
        i++;
      } else if (/^\d+$/.test(tokens[i])) {
        loseCount = parseInt(tokens[i++]);
      } else {
        continue; // unknown format, skip
      }
      if (i < tokens.length) {
        const statusName = tokens[i++];
        effects.push({
          raw: `Lose ${loseAll ? 'All' : loseCount} ${statusName}`,
          value: loseCount,
          move: 'Lose',
          target: statusName,
          all: loseAll
        });
      }
      continue;
    }

    // "Add N CardName to Discard" — e.g. "Add 2 Slimed to Discard"
    if (tokens[i].toLowerCase() === 'add') {
      i++;
      if (i < tokens.length && /^\d+$/.test(tokens[i])) {
        const count = parseInt(tokens[i++]);
        const nameTokens = [];
        while (i < tokens.length && tokens[i].toLowerCase() !== 'to') {
          nameTokens.push(tokens[i++]);
        }
        if (i < tokens.length && tokens[i].toLowerCase() === 'to') i++;
        if (i < tokens.length && tokens[i].toLowerCase() === 'discard') i++;
        if (nameTokens.length > 0) {
          const cardName = nameTokens.join(' ');
          effects.push({ raw: `Add ${count} ${cardName} to Discard`, value: count, move: 'AddToDiscard', target: cardName, addons: [] });
        }
      }
      continue;
    }

    // "Spawn <EnemyName>" — collect name tokens until next digit or end
    if (tokens[i].toLowerCase() === 'spawn') {
      i++;
      const nameTokens = [];
      while (i < tokens.length && !/^\d+$/.test(tokens[i])) {
        nameTokens.push(tokens[i++]);
      }
      if (nameTokens.length > 0) {
        const spawnName = nameTokens.join(' ');
        effects.push({ raw: `Spawn ${spawnName}`, move: 'spawn', target: spawnName, value: 0, addons: [] });
      }
      continue;
    }

    if (!tokens[i].match(/^\d+$/)) { i++; continue; }
    const numIdx  = i;                  // index of the number token
    const value   = parseInt(tokens[i++]);
    if (i >= tokens.length) break;
    const move    = tokens[i++];
    const moveLow = move.toLowerCase();
    // If the token immediately before the number was "Gain" or "Get", this is a self-buff
    const prevToken = numIdx > 0 ? tokens[numIdx - 1].toLowerCase() : '';
    const isSelfBuff = prevToken === 'gain' || prevToken === 'get';

    if (moveLow === 'dmg') {
      const addons = [];
      while (i < tokens.length && PATTERN_ADDONS.has(tokens[i].toLowerCase())) {
        addons.push(tokens[i++]);
      }
      effects.push({ raw: `${value} ${move}`, value, move: 'Dmg', addons, target: null });
    } else if (moveLow === 'magic' && i < tokens.length && tokens[i].toLowerCase() === 'dmg') {
      i++; // consume 'Dmg'
      const KNOWN_ELEMENTS = new Set(['fire']);
      let element = null;
      if (i < tokens.length && KNOWN_ELEMENTS.has(tokens[i].toLowerCase())) {
        element = tokens[i++];
      }
      const addons = [];
      while (i < tokens.length && PATTERN_ADDONS.has(tokens[i].toLowerCase())) {
        addons.push(tokens[i++]);
      }
      effects.push({ raw: `${value} Magic Dmg${element ? ' ' + element : ''}`, value, move: 'Magic Dmg', element: element ? element.toLowerCase() : null, addons, target: null });
    } else if (moveLow === 'block') {
      effects.push({ raw: `${value} ${move}`, value, move: 'Block', addons: [], target: null });
    } else if (moveLow === 'heal') {
      effects.push({ raw: `${value} ${move}`, value, move: 'Heal', addons: [], target: null });
    } else if (moveLow === 'pain') {
      effects.push({ raw: `${value} Pain`, value, move: 'pain', addons: [], target: null });
    } else if (PATTERN_STATUSES.has(moveLow)) {
      // "Gain/Get X Status" → enemy self-buff (Get); otherwise inflict on player
      const moveType = isSelfBuff ? 'Get' : 'Inflict';
      effects.push({ raw: `${value} ${move}`, value, move: moveType, addons: [], target: move });
    }
    // Unknown move type — skip silently
  }
  return effects;
}

/**
 * Detect if a string contains dice notation (e.g. "D6", "D8x3", "D8x2 + D6x2").
 * @param {string} str
 * @returns {boolean}
 */
function hasDiceNotation(str) {
  return /D\d+/i.test(str);
}

/**
 * Roll dice from notation like "D6", "D8x3", "D8x2 + D6x2".
 * Each die is rolled individually (not summed before rolling).
 * @param {string} notation - Raw string containing dice notation
 * @returns {{ total: number, rolls: Array<{die:number, result:number}> }}
 */
function rollDiceNotation(notation) {
  const rolls = [];
  // Match all dice groups like "D8x2" or "D6" or "D10x3"
  const diceRegex = /(\d*)[xX]?D(\d+)(?:[xX](\d+))?/gi;
  let match;
  let str = notation.replace(/\+/g, ' ');
  while ((match = diceRegex.exec(str)) !== null) {
    // Handle both "D8x2" (dieSize=8, count=2) and "D8x2" written as "2xD8"
    let count = 1;
    let sides = parseInt(match[2]);
    if (match[1] && match[1] !== '') count = parseInt(match[1]);
    if (match[3] && match[3] !== '') count = parseInt(match[3]);
    for (let i = 0; i < count; i++) {
      const result = Math.floor(Math.random() * sides) + 1;
      rolls.push({ die: sides, result });
    }
  }
  const total = rolls.reduce((sum, r) => sum + r.result, 0);
  return { total, rolls };
}

/**
 * Parse a damage value from an effect, resolving dice notation if present.
 * For dice attacks (D6/D8/etc.), rolls each die individually.
 * @param {Object} effect - Effect object
 * @param {Object} [options] - Options: { canReroll, rerollsAvailable }
 * @returns {{ value: number, isDiceAttack: boolean, rollDetails: string }}
 */
function resolveEffectValue(effect) {
  const raw = effect.raw || '';
  if (hasDiceNotation(raw)) {
    const { total, rolls } = rollDiceNotation(raw);
    const rollStr = rolls.map(r => `d${r.die}:${r.result}`).join(', ');
    return { value: total, isDiceAttack: true, rollDetails: rollStr };
  }
  return { value: effect.value || 0, isDiceAttack: false, rollDetails: null };
}

/**
 * Roll intent for all enemies
 */
function rollAllEnemyIntents() {
  combatState.enemies.forEach(enemy => {
    if (enemy.health > 0) {
      // Reset Curl Up trigger at the start of each new round
      enemy.curlUpTriggeredThisTurn = false;
      // Clear justSpawned flag so they act normally next turn, then roll their real intent
      if (enemy.justSpawned) {
        enemy.justSpawned = false;
      }
      rollEnemyIntent(enemy);
    }
  });
}

/**
 * Roll intent for a single enemy.
 * - Ordered pattern enemies advance through their turn list each turn.
 * - Random pattern enemies now execute their pattern string (dice are legacy).
 * @param {Object} enemy - Enemy state object
 */
function rollEnemyIntent(enemy) {
  enemy.currentIntent = [];

  if (enemy.patternType === 'ordered' && enemy.patternTurns && enemy.patternTurns.length > 0) {
    // Advance through the ordered pattern
    const turns = enemy.patternTurns;
    let idx = enemy.patternTurnIndex || 0;

    // "Next: Repeat" is a loop marker — skip it and jump to Turn 1 without executing it
    const isRepeatMarker = (t) => t && t.label.toLowerCase() === 'next' && t.description.toLowerCase().trim() === 'repeat';
    if (isRepeatMarker(turns[idx])) {
      idx = 0;
    }

    const current = turns[idx];

    // Build a pseudo-face by parsing the description into executable effects
    const parsedTurn = parsePatternDescToEffects(current.description);
    const isUnknownIntent = /unknown intent/i.test(current.description);
    const pseudoFace = { isBlank: isUnknownIntent, effects: parsedTurn.effects, raw: parsedTurn.text };
    enemy.currentIntent.push({ faceIndex: idx, face: pseudoFace, resolved: false });

    // Advance index for next turn
    let nextIdx = idx + 1;
    const isCurrentNext = current.label.toLowerCase() === 'next';

    if (isCurrentNext) {
      // "Next: [action]" — stay here forever (looping action, not Repeat which was skipped above)
      nextIdx = idx;
    } else if (nextIdx >= turns.length) {
      // Ran past the end — loop back to Turn 1 (skipping any Repeat marker)
      nextIdx = 0;
    } else if (isRepeatMarker(turns[nextIdx])) {
      // The very next entry is "Next: Repeat" — skip it and loop to Turn 1
      nextIdx = 0;
    }
    enemy.patternTurnIndex = nextIdx;

  } else {
    // Random: execute the pattern description (dice are the old design)
    const rawPatternDesc = (enemy.pattern || '').replace(/^Always:\s*/i, '').trim();
    // Substitute any Determined(X-Y) tokens with the pre-rolled combat values
    const patternDesc = applyDetermined(rawPatternDesc, enemy);
    const multiAttack = enemy.statuses['multi_attack'] || 1;
    const isForgetful = !!enemy.statuses['forgetful'];

    // Split probability branches for Forgetful tracking
    const branches = (patternDesc.includes('%') && patternDesc.includes('/'))
      ? patternDesc.split('/').map(s => s.trim()).filter(s => /^\d+%/.test(s))
      : [];

    for (let i = 0; i < multiAttack; i++) {
      let effects;
      let resolvedText;

      if (isForgetful && branches.length > 1) {
        // Forgetful: cycle through all branches before repeating
        if (enemy.rolledFaces.size >= branches.length) {
          enemy.rolledFaces.clear();
          enemy.statuses['forgetful']--;
          if (enemy.statuses['forgetful'] <= 0) delete enemy.statuses['forgetful'];
        }
        const availableIndices = branches.map((_, idx) => idx)
          .filter(idx => !enemy.rolledFaces.has(idx));
        const chosen = availableIndices[Math.floor(Math.random() * availableIndices.length)];
        enemy.rolledFaces.add(chosen);
        resolvedText = branches[chosen].replace(/^\d+%\s*/, '').trim();
        effects = parseSimplePatternDesc(resolvedText);
      } else {
        const parsed = parsePatternDescToEffects(patternDesc);
        effects = parsed.effects;
        resolvedText = parsed.text;
      }

      const isBlank = effects.length === 0 || /unknown intent/i.test(resolvedText);
      const pseudoFace = { isBlank, effects, raw: resolvedText };
      enemy.currentIntent.push({ faceIndex: 0, face: pseudoFace, resolved: false });
    }
  }

  // Split override: if HP ≤ 50% and split not yet triggered, override intent to Splitting
  if (enemy.splitAbility && !enemy.splitAbility.triggered && enemy.health <= enemy.maxHealth * 0.5) {
    enemy.currentIntent = [{
      faceIndex: 0,
      face: {
        isBlank: false,
        effects: [{ raw: 'Splitting', value: 0, move: 'Split', addons: [] }],
        raw: `Splitting (×${enemy.splitAbility.count} ${enemy.splitAbility.spawnName})`
      },
      resolved: false
    }];
    enemy.splitAbility.splitting = true;
    addLog(`${enemy.name} begins to split!`, 'warning');
    return;
  }

  // Log intent (shows resolved text, not the full probability string)
  const intentStr = enemy.currentIntent.map(intent => intent.face.raw || 'Unknown').join(', ');
  addLog(`${enemy.name} intends: ${intentStr}`, 'warning');
}

// ============== PLAYER ACTIONS ==============

/**
 * Roll a player die
 * @param {string} diceId - ID of the die to roll
 * @returns {Object} Result with success status and face
 */
function rollPlayerDie(diceId) {
  if (!combatState || combatState.phase !== 'player_action') {
    return { success: false, error: 'Cannot roll dice now' };
  }

  const die = combatState.playerDice.find(d => d.id === diceId);
  if (!die) {
    return { success: false, error: 'Die not found' };
  }

  if (die.isExhausted) {
    return { success: false, error: 'Die is exhausted' };
  }

  // Check ally is alive for ally dice
  if (die.source === 'ally') {
    const ally = combatState.allies.find(a => a.id === die.id);
    if (!ally || !ally.isAlive) {
      return { success: false, error: 'Ally is dead' };
    }
  }

  // Calculate energy cost (may be randomized by Confused)
  let energyCost = die.energyCost;
  const confusedStacks = combatState.player.statuses['confused'] || 0;
  if (confusedStacks > 0) {
    energyCost = Math.floor(Math.random() * (combatState.player.maxEnergy + 1));
    addLog(`Confused! Die costs ${energyCost} energy`, 'warning');
  }

  // Check energy
  if (combatState.player.energy < energyCost) {
    return { success: false, error: 'Not enough energy' };
  }

  // Spend energy
  combatState.player.energy -= energyCost;

  // Roll the die
  const faceIndex = Math.floor(Math.random() * die.faces.length);
  const face = die.faces[faceIndex];

  die.currentFace = face;
  die.currentFaceIndex = faceIndex;
  die.isRolled = true;
  die.isConfirmed = false;

  addLog(`Rolled ${die.name}: ${face.raw || 'Blank'}`, 'info');

  // Process Cantrip effects immediately
  if (!face.isBlank) {
    face.effects.forEach(effect => {
      if (effect.addons && effect.addons.includes('Cantrip')) {
        processCantripEffect(effect, die);
      }
    });
  }

  return { success: true, face: face, diceId: diceId, faceIndex: faceIndex };
}

/**
 * Reroll a player die
 * @param {string} diceId - ID of the die to reroll
 * @returns {Object} Result
 */
function rerollPlayerDie(diceId) {
  if (!combatState || combatState.phase !== 'player_action') {
    return { success: false, error: 'Cannot reroll now' };
  }

  const die = combatState.playerDice.find(d => d.id === diceId);
  if (!die || !die.isRolled || die.isConfirmed) {
    return { success: false, error: 'Cannot reroll this die' };
  }

  if (combatState.player.rerolls < 1) {
    return { success: false, error: 'No rerolls remaining' };
  }

  // Spend reroll
  combatState.player.rerolls--;

  // Reroll
  const faceIndex = Math.floor(Math.random() * die.faces.length);
  const face = die.faces[faceIndex];

  die.currentFace = face;
  die.currentFaceIndex = faceIndex;

  addLog(`Rerolled ${die.name}: ${face.raw || 'Blank'}`, 'info');

  // Process Cantrip effects
  if (!face.isBlank) {
    face.effects.forEach(effect => {
      if (effect.addons && effect.addons.includes('Cantrip')) {
        processCantripEffect(effect, die);
      }
    });
  }

  return { success: true, face: face, diceId: diceId, faceIndex: faceIndex };
}

/**
 * Confirm a die roll and apply effects
 * Dice can be used multiple times per turn as long as player has energy
 * @param {string} diceId - ID of the die
 * @param {Object} targets - Target information { enemyId, allyId, etc. }
 * @returns {Object} Result
 */
function confirmDie(diceId, targets = {}) {
  if (!combatState || combatState.phase !== 'player_action') {
    return { success: false, error: 'Cannot confirm now' };
  }

  const die = combatState.playerDice.find(d => d.id === diceId);
  if (!die || !die.isRolled) {
    return { success: false, error: 'Cannot confirm this die' };
  }

  const face = die.currentFace;

  // Process effects (skip Cantrip effects as they were already processed)
  if (!face.isBlank) {
    face.effects.forEach(effect => {
      if (!effect.addons || !effect.addons.includes('Cantrip')) {
        processEffect(effect, die, targets);
      }
    });
  }

  // Check for Exhert
  let hasExhert = false;
  if (face.effects) {
    face.effects.forEach(effect => {
      if (effect.addons) {
        const exhertAddon = effect.addons.find(a => a.startsWith('Exhert'));
        if (exhertAddon) {
          hasExhert = true;
          die.isExhausted = true;
          // Parse duration if present
          const match = exhertAddon.match(/Exhert\s*\((\d+)\)/i);
          die.exhertDuration = match ? parseInt(match[1]) : Infinity;
          addLog(`${die.name} is exhausted!`, 'warning');
        }
      }
    });
  }

  // Reset dice state so it can be rolled again (unless exhausted)
  if (!hasExhert) {
    die.isRolled = false;
    die.isConfirmed = false;
    die.currentFace = null;
    die.currentFaceIndex = null;
  } else {
    die.isConfirmed = true;
  }

  // Check for victory after dealing damage
  checkVictoryCondition();

  return { success: true };
}

/**
 * Check if all enemies are defeated and set victory phase
 */
function checkVictoryCondition() {
  if (!combatState || combatState.phase === 'victory' || combatState.phase === 'defeat') {
    return;
  }

  const allDead = combatState.enemies.every(e => e.health <= 0);
  if (allDead) {
    combatState.phase = 'victory';
    addLog('All enemies defeated!', 'success');
  }
}

/**
 * Use player's dash to gain Dodge
 * @returns {Object} Result
 */
function useDash() {
  if (!combatState || combatState.phase !== 'player_action') {
    return { success: false, error: 'Cannot dash now' };
  }

  if (combatState.player.dash < 1) {
    return { success: false, error: 'No dash available' };
  }

  // Calculate energy cost (may be randomized by Confused)
  let energyCost = 1;
  const confusedStacks = combatState.player.statuses['confused'] || 0;
  if (confusedStacks > 0) {
    energyCost = Math.floor(Math.random() * (combatState.player.maxEnergy + 1));
    addLog(`Confused! Dash costs ${energyCost} energy`, 'warning');
  }

  if (combatState.player.energy < energyCost) {
    return { success: false, error: 'Not enough energy' };
  }

  // Spend energy and dash
  combatState.player.energy -= energyCost;
  combatState.player.dash--;

  // Gain Dodge
  combatState.player.statuses['dodge'] = (combatState.player.statuses['dodge'] || 0) + 1;

  // Check for Ruptured
  const rupturedStacks = combatState.player.statuses['ruptured'] || 0;
  if (rupturedStacks > 0) {
    const damage = 3 * rupturedStacks;
    combatState.player.health -= damage;
    combatState.player.statuses['ruptured']--;
    if (combatState.player.statuses['ruptured'] <= 0) {
      delete combatState.player.statuses['ruptured'];
    }
    addLog(`Ruptured! Took ${damage} damage from dashing`, 'danger');
  }

  addLog('Used Dash to gain 1 Dodge!', 'success');

  return { success: true };
}

// ============== SPELL SYSTEM ==============

/**
 * Cast a spell
 * @param {string} spellName - Name of the spell
 * @param {Object} targets - Target information
 * @returns {Object} Result
 */
function castSpell(spellName, targets = {}) {
  if (!combatState || combatState.phase !== 'player_action') {
    return { success: false, error: 'Cannot cast spells now' };
  }

  // Find spell
  const spell = combatState.spells.find(s => s.name === spellName);
  if (!spell) {
    return { success: false, error: 'Spell not found' };
  }

  // Check SingleCast
  if (spell.keywords.includes('SingleCast') && combatState.usedSingleCast[spellName]) {
    return { success: false, error: 'Already used this combat' };
  }

  // Check Cooldown
  if (spell.keywords.includes('Cooldown') && combatState.spellCooldowns[spellName]) {
    return { success: false, error: 'On cooldown' };
  }

  // Calculate mana cost
  let cost = spell.cost;
  const castCount = combatState.spellCasts[spellName] || 0;

  // Channel: costs 1 less each cast (min 1)
  if (spell.keywords.includes('Channel')) {
    cost = Math.max(1, cost - castCount);
  }

  // Deplete: costs 1 more each cast
  if (spell.keywords.includes('Deplete')) {
    cost = cost + castCount;
  }

  // Check mana
  if (combatState.player.mana < cost) {
    return { success: false, error: 'Not enough mana' };
  }

  // Spend mana
  combatState.player.mana -= cost;

  // Track casts
  combatState.spellCasts[spellName] = castCount + 1;

  // Set cooldown
  if (spell.keywords.includes('Cooldown')) {
    combatState.spellCooldowns[spellName] = true;
  }

  // Mark SingleCast as used
  if (spell.keywords.includes('SingleCast')) {
    combatState.usedSingleCast[spellName] = true;
  }

  addLog(`Cast ${spellName}!`, 'info');

  // Calculate INT bonus if applicable
  const intBonus = spell.affectedByBonus ? combatState.player.bonuses.intelligence : 0;

  // Future keyword: queue effects to fire at the start of next turn instead of now
  if (spell.keywords.includes('Future')) {
    if (!combatState.futureEffects) combatState.futureEffects = [];
    spell.effects.forEach(effect => {
      const modifiedEffect = { ...effect };
      const isMagicDmgFuture = effect.move && ['magic dmg', 'magic_dmg'].includes(effect.move.toLowerCase());
      if (modifiedEffect.value && spell.affectedByBonus && !isMagicDmgFuture) modifiedEffect.value += intBonus;
      combatState.futureEffects.push({ effect: modifiedEffect, spell, targets });
    });
    addLog(`${spellName}: effects queued for next turn!`, 'info');
    return { success: true };
  }

  spell.effects.forEach(effect => {
    // Clone effect and apply INT bonus (skip magic dmg — calculateMoveValue handles it via Arcane)
    const modifiedEffect = { ...effect };
    const isMagicDmg = effect.move && ['magic dmg', 'magic_dmg'].includes(effect.move.toLowerCase());
    if (modifiedEffect.value && spell.affectedByBonus && !isMagicDmg) {
      modifiedEffect.value += intBonus;
    }
    processSpellEffect(modifiedEffect, spell, targets);
  });

  return { success: true };
}

// ============== EFFECT PROCESSING ==============

/**
 * Process a Cantrip effect (triggers immediately on roll)
 * @param {Object} effect - Effect data
 * @param {Object} die - Die that rolled this effect
 */
function processCantripEffect(effect, die) {
  // Auto-target based on preferred target
  const targets = getAutoTargets(effect);
  processEffect(effect, die, targets, true);
  addLog(`Cantrip: ${effect.raw}`, 'info');
}

/**
 * Process an effect from a die face
 * @param {Object} effect - Effect data
 * @param {Object} die - Die source
 * @param {Object} targets - Target information
 * @param {boolean} isCantrip - Whether this is a cantrip (auto-targeted)
 */
function processEffect(effect, die, targets, isCantrip = false) {
  if (!effect || !effect.move) return;

  const move = effect.move.toLowerCase();
  let value = effect.value || 0;

  // Apply stat bonuses
  value = calculateMoveValue(move, value, die);

  // Get targets based on addons
  const resolvedTargets = resolveTargets(effect, targets, isCantrip);

  // Process based on move type
  switch (move) {
    case 'dmg':
      resolvedTargets.enemies.forEach(enemy => {
        dealDamage(enemy, value, effect.addons || []);
      });
      break;

    case 'magic dmg':
    case 'magic_dmg': {
      const magicAddons = (effect.addons || []).filter(a => !['DamagedEnemies', 'LeftmostRightmost'].includes(a));
      resolvedTargets.enemies.forEach(enemy => {
        dealDamage(enemy, value, ['magic', ...magicAddons]);
        if (effect.element) {
          applyElement(enemy, effect.element, value, magicAddons);
        }
      });
      break;
    }

    case 'block':
      resolvedTargets.allies.forEach(ally => {
        addBlock(ally, value);
      });
      if (resolvedTargets.player) {
        addBlock(combatState.player, value);
      }
      break;

    case 'heal':
      resolvedTargets.allies.forEach(ally => {
        healTarget(ally, value);
      });
      if (resolvedTargets.player) {
        healTarget(combatState.player, value);
      }
      break;

    case 'mana':
      combatState.player.mana = Math.min(
        combatState.player.mana + value,
        combatState.player.maxMana
      );
      addLog(`Gained ${value} mana`, 'info');
      break;

    case 'reroll':
      combatState.player.rerolls += value;
      addLog(`Gained ${value} reroll(s)`, 'info');
      break;

    case 'pain':
      dealDamage(combatState.player, value, ['self']);
      break;

    case 'get':
      // Give status to self
      const statusName = effect.target ? effect.target.toLowerCase() : '';
      if (statusName) {
        applyStatus(combatState.player, statusName, value);
        addLog(`Gained ${value} ${effect.target}`, 'info');
      }
      break;

    case 'inflict':
      // Inflict status on targets
      const inflictStatus = effect.target ? effect.target.toLowerCase() : '';
      if (inflictStatus) {
        resolvedTargets.enemies.forEach(enemy => {
          applyStatus(enemy, inflictStatus, value);
          addLog(`Inflicted ${value} ${effect.target} on ${enemy.name}`, 'info');
        });
      }
      break;

    case 'cleanse':
      // Remove debuffs
      if (resolvedTargets.player) {
        cleanseDebuffs(combatState.player, value);
      }
      resolvedTargets.allies.forEach(ally => {
        cleanseDebuffs(ally, value);
      });
      break;

    case 'spawn':
      // Spawn creature - would need creature data
      addLog(`Spawned ${effect.target || 'creature'}`, 'info');
      break;

    case 'alter':
      // Transform - would need form data
      addLog(`Altered into ${effect.target || 'new form'}`, 'info');
      break;

    case 'assassinate': {
      resolvedTargets.enemies.forEach(enemy => {
        const adds = (effect.addons || []).map(a => a.toLowerCase());
        let threshold = value || 0;
        if (adds.includes('halfmax')) {
          threshold = Math.ceil(enemy.maxHealth / 2);
        } else if (adds.includes('fullmax')) {
          threshold = enemy.maxHealth;
        }
        if (enemy.health <= threshold) {
          enemy.health = 0;
          addLog(`Assassinated ${enemy.name}!`, 'success');
        }
      });
      break;
    }

    case 'set': {
      // Set target's health to a fixed value (Mend spell)
      const setVal = effect.value || value;
      // Prefer ally target, then player
      const setTarget = resolvedTargets.allies.length > 0
        ? resolvedTargets.allies[0]
        : (resolvedTargets.player ? combatState.player : null);
      if (setTarget) {
        setTarget.health = Math.min(setVal, setTarget.maxHealth);
        if (setTarget === combatState.player) window.health = setTarget.health;
        addLog(`Set ${setTarget.name || 'Player'} health to ${setVal}`, 'success');
      }
      break;
    }

    case 'vitality':
      combatState.player.maxHealth += value;
      combatState.player.health += value;
      addLog(`Gained ${value} max health`, 'success');
      break;

    case 'gain': {
      // "Gain X Reroll" / "Gain X Mana" / "Gain X <StatusName>"
      const gainWhat = (effect.addons || []).join(' ').toLowerCase();
      const gainAmt = parseInt((effect.addons || [])[0]) || value || 1;
      const gainThing = (effect.addons || []).slice(1).join(' ').toLowerCase();
      if (gainThing === 'reroll' || gainWhat === 'reroll') {
        const amt = typeof value === 'number' && value > 0 ? value : gainAmt;
        combatState.player.rerolls += amt;
        addLog(`Gained ${amt} reroll(s)`, 'info');
      } else if (gainThing === 'mana' || gainWhat.includes('mana')) {
        const manaAmt = gainAmt;
        combatState.player.mana = Math.min(combatState.player.mana + manaAmt, combatState.player.maxMana);
        addLog(`Gained ${manaAmt} mana`, 'info');
      } else if (gainThing) {
        applyStatus(combatState.player, gainThing.replace(/\s+/g, '_'), gainAmt);
        addLog(`Gained ${gainAmt} ${gainThing}`, 'info');
      }
      break;
    }
  }
}

/**
 * Apply stat bonus to a move value
 * @param {string} move - Move type
 * @param {number} value - Base value
 * @param {Object} die - Die source (for weapon finesse check)
 * @returns {number} Modified value
 */
function calculateMoveValue(move, value, die) {
  const bonuses = combatState.player.bonuses || {};

  // Ensure value is a valid number
  const baseValue = (typeof value === 'number' && !isNaN(value)) ? value : 0;

  // Check for Finesse on weapons
  const hasFinesse = die && die.tags && die.tags.includes('finesse');

  // Get bonus values with fallback to 0
  const strBonus = bonuses.strength || 0;
  const dexBonus = bonuses.dexterity || 0;
  const intBonus = bonuses.intelligence || 0;
  const chaBonus = bonuses.charisma || 0;

  // Combat status bonuses — these now include stat-derived power/defense set at combat init
  // (statuses['power'] = strBonus at start; statuses['defense'] = dexBonus at start)
  const playerStatuses = combatState.player.statuses || {};
  const combatPowerBonus = playerStatuses['power'] || 0;
  const combatDefenseBonus = playerStatuses['defense'] || 0;

  switch (move) {
    case 'dmg':
    case 'pain':
    case 'assassinate':
      if (hasFinesse) {
        // Finesse weapons scale with Dexterity, not Strength.
        // combatPowerBonus includes the str-derived _statPower; subtract that and add dex instead.
        const statPowerOffset = combatState.player._statPower || 0;
        return baseValue + dexBonus + Math.max(0, combatPowerBonus - statPowerOffset);
      }
      return baseValue + combatPowerBonus;

    case 'magic dmg':
    case 'magic_dmg':
      // Magic damage scales with Arcane status (not Power)
      return baseValue + (playerStatuses['arcane'] || 0);

    case 'block':
      // combatDefenseBonus already includes dex-derived defense set at combat init
      return baseValue + combatDefenseBonus;

    case 'heal':
    case 'vitality':
      return baseValue + intBonus;

    case 'mana':
      return baseValue;

    case 'reroll':
      return baseValue + chaBonus;

    case 'get':
    case 'inflict':
    case 'cleanse':
      // Persistence replaces direct charisma scaling for status applications
      return baseValue + (playerStatuses['persistence'] || 0);

    default:
      return baseValue;
  }
}

/**
 * Resolve targets based on effect addons
 * @param {Object} effect - Effect data
 * @param {Object} targets - Specified targets
 * @param {boolean} isCantrip - Auto-target for cantrip
 * @returns {Object} Resolved targets { enemies: [], allies: [], player: bool }
 */
function resolveTargets(effect, targets, isCantrip) {
  const result = { enemies: [], allies: [], player: false };
  const addons = effect.addons || [];

  // Get preferred target from MOVES_DATA
  const moveData = typeof MOVES_DATA !== 'undefined' ? MOVES_DATA[effect.move?.toLowerCase()] : null;
  const preferredTarget = moveData?.preferredTarget || 'Enemy';

  // DamagedEnemies: all enemies that have taken damage (below max health)
  if (addons.includes('DamagedEnemies')) {
    result.enemies = combatState.enemies.filter(e => e.health > 0 && e.health < e.maxHealth);
    return result;
  }

  // LeftmostRightmost: leftmost and rightmost alive enemies by position
  if (addons.includes('LeftmostRightmost')) {
    const alive = combatState.enemies.filter(e => e.health > 0).sort((a, b) => (a.position || 0) - (b.position || 0));
    if (alive.length > 0) result.enemies.push(alive[0]);
    if (alive.length > 1) result.enemies.push(alive[alive.length - 1]);
    return result;
  }

  // Wide: all enemies (for damage) or all allies (for support)
  if (addons.includes('Wide')) {
    if (preferredTarget === 'Enemy') {
      result.enemies = combatState.enemies.filter(e => e.health > 0);
    } else {
      result.allies = combatState.allies.filter(a => a.isAlive);
      result.player = true;
    }
    return result;
  }

  // Overload: everything
  if (addons.includes('Overload')) {
    result.enemies = combatState.enemies.filter(e => e.health > 0);
    result.allies = combatState.allies.filter(a => a.isAlive);
    result.player = true;
    return result;
  }

  // Cleave: target + adjacent
  if (addons.includes('Cleave') && targets.enemyId) {
    const targetEnemy = combatState.enemies.find(e => e.id === targets.enemyId);
    if (targetEnemy) {
      result.enemies.push(targetEnemy);
      // Add adjacent enemies
      const pos = targetEnemy.position;
      combatState.enemies.forEach(e => {
        if (e.health > 0 && (e.position === pos - 1 || e.position === pos + 1)) {
          result.enemies.push(e);
        }
      });
    }
    return result;
  }

  // Single target
  if (isCantrip) {
    // Auto-target for cantrip
    if (preferredTarget === 'Enemy') {
      const aliveEnemies = combatState.enemies.filter(e => e.health > 0);
      if (aliveEnemies.length > 0) {
        result.enemies.push(aliveEnemies[Math.floor(Math.random() * aliveEnemies.length)]);
      }
    } else {
      result.player = true;
    }
  } else {
    // Use specified target
    if (targets.enemyId) {
      const enemy = combatState.enemies.find(e => e.id === targets.enemyId);
      if (enemy) result.enemies.push(enemy);
    }
    if (targets.allyId) {
      const ally = combatState.allies.find(a => a.id === targets.allyId);
      if (ally) result.allies.push(ally);
    }
    if (targets.self || preferredTarget.includes('Self')) {
      result.player = true;
    }
  }

  // Default to player for self-targeting moves
  if (result.enemies.length === 0 && result.allies.length === 0 && !result.player) {
    if (preferredTarget.includes('Self') || preferredTarget.includes('Ally')) {
      result.player = true;
    }
  }

  return result;
}

/**
 * Get auto-targets for an effect
 * @param {Object} effect - Effect data
 * @returns {Object} Targets
 */
function getAutoTargets(effect) {
  const moveData = typeof MOVES_DATA !== 'undefined' ? MOVES_DATA[effect.move?.toLowerCase()] : null;
  const preferredTarget = moveData?.preferredTarget || 'Enemy';

  if (preferredTarget === 'Enemy') {
    const aliveEnemies = combatState.enemies.filter(e => e.health > 0);
    if (aliveEnemies.length > 0) {
      return { enemyId: aliveEnemies[Math.floor(Math.random() * aliveEnemies.length)].id };
    }
  }

  return { self: true };
}

// ============== COMBAT ACTIONS ==============

/**
 * Apply the Fire element effect: inflict 1 Burn if the target has none.
 * @param {Object} target - Target entity
 */
function applyFireElement(target) {
  applyElement(target, 'fire');
}

/**
 * Apply an element's on-hit effect to a target.
 * @param {Object} target - Target entity
 * @param {string} element - Element name (fire/water/poison/dark/blood/electric/earth)
 * @param {number} [electricDamage] - Damage to chain for electric element
 * @param {Array} [electricAddons] - Addons to pass for electric chains
 */
function applyElement(target, element, electricDamage = 0, electricAddons = []) {
  if (!target || !target.statuses || !element || element === 'n/a') return;
  switch (element.toLowerCase()) {
    case 'fire':
      if (!(target.statuses['burn'] > 0)) {
        applyStatus(target, 'burn', 1);
        addLog(`Fire: ${target.name || 'Target'} ignited! +1 Burn`, 'warning');
      }
      break;
    case 'water':
      applyStatus(target, 'wet', 1);
      addLog(`Water: ${target.name || 'Target'} is now Wet!`, 'info');
      if (target.statuses['burn']) {
        delete target.statuses['burn'];
        addLog(`Water: Burn extinguished on ${target.name || 'Target'}!`, 'info');
      }
      break;
    case 'poison':
      applyStatus(target, 'poison', 1);
      addLog(`Poison: ${target.name || 'Target'} poisoned! +1 Poison`, 'warning');
      break;
    case 'dark':
      if (!(target.statuses['blind'] > 0)) {
        applyStatus(target, 'blind', 1);
        addLog(`Dark: ${target.name || 'Target'} blinded! +1 Blind`, 'warning');
      }
      break;
    case 'blood':
      if (!(target.statuses['bleed'] > 0)) {
        applyStatus(target, 'bleed', 1);
        addLog(`Blood: ${target.name || 'Target'} bleeding! +1 Bleed`, 'warning');
      }
      break;
    case 'electric':
      // Electric chains to adjacent Wet targets — handled at call site with electricDamage
      if (electricDamage > 0 && target.statuses['wet'] && target.statuses['wet'] > 0) {
        const pos = target.position;
        combatState.enemies.forEach(adj => {
          if (adj !== target && adj.health > 0 && adj.statuses && adj.statuses['wet']
              && (adj.position === pos - 1 || adj.position === pos + 1)) {
            dealDamage(adj, electricDamage, ['magic', ...electricAddons]);
            addLog(`Electric: chained ${electricDamage} damage to ${adj.name}!`, 'info');
          }
        });
      }
      break;
    case 'earth':
      // No on-hit effect
      break;
  }
}

/**
 * Deal damage to a target
 * @param {Object} target - Target entity
 * @param {number} damage - Damage amount
 * @param {Array} addons - Effect addons
 */
function dealDamage(target, damage, addons = []) {
  // Validate damage is a valid number
  let dmg = (typeof damage === 'number' && !isNaN(damage)) ? damage : 0;
  if (dmg <= 0) return;

  // Blind: player has 30% miss chance per hit (not self-damage); luck gives advantage (roll twice, take higher)
  if (!addons.includes('self') && target !== combatState.player &&
      combatState.player.statuses && combatState.player.statuses['blind'] > 0) {
    if (rollWithLuckAdvantage() < 0.3) {
      if (combatState._hitLog !== undefined) {
        combatState._hitLog.push({ targetId: target.id || null, missed: true });
      }
      // Dead Eye: miss resets the streak
      combatState._deadEyeBonus = 0;
      combatState._deadEyeTarget = null;
      addLog('Attack missed! (Blind)', 'warning');
      return;
    }
  }

  // Flat melee attack bonus from items (Focus Crystal, Beefy Ring, etc.)
  // Applied whenever a melee hit is dealt by the player
  if (addons.includes('melee') && combatState._flatAttackBonus) {
    dmg += combatState._flatAttackBonus;
  }

  // Offensive thorns: attacker's own thorns add to their melee damage
  if (addons.includes('melee') && target !== combatState.player) {
    const playerThorns = (combatState.player && combatState.player.statuses['thorns']) || 0;
    if (playerThorns > 0) dmg += playerThorns;
  }

  // Record hit for multi-hit visual playback
  if (combatState._hitLog !== undefined && target !== combatState.player && !addons.includes('self')) {
    combatState._hitLog.push({ targetId: target.id || null, dmg });
  }

  // Pen Nib: every 10th attack deals double damage
  if (combatState && combatState._penNibDouble) {
    dmg *= 2;
  }

  // Double Damage: player's attacks deal double damage for X turns
  if (!addons.includes('self') && target !== combatState.player && combatState.player.statuses['double_damage']) {
    dmg *= 2;
  }

  // Check Engage (x2 on full health)
  if (addons.includes('Engage') && target.health === target.maxHealth) {
    dmg *= 2;
  }

  // Check Enfeebled (double damage taken)
  const enfeebledStacks = target.statuses['enfeebled'] || 0;
  if (enfeebledStacks > 0) {
    dmg *= 2;
  }

  // Check Vulnerable (50% more incoming damage)
  if (target.statuses['vulnerable']) {
    dmg = Math.ceil(dmg * 1.5);
  }

  // Wet: fire immunity is handled via applyStatus interception (Burn blocked when Wet)
  // Electric chaining is handled in applyElement

  // Check Bruise (melee/ranged attacks deal +1 per stack; pure magic damage is exempt)
  const bruiseStacks = target.statuses['bruise'] || 0;
  const isMeleeOrRanged = !addons.includes('self') &&
    (!addons.includes('magic') || addons.includes('melee') || addons.includes('ranged'));
  if (bruiseStacks > 0 && isMeleeOrRanged) {
    dmg += bruiseStacks;
  }

  // Check Dodge
  const dodgeStacks = target.statuses['dodge'] || 0;
  if (dodgeStacks > 0 && !addons.includes('self')) {
    target.statuses['dodge']--;
    if (target.statuses['dodge'] <= 0) {
      delete target.statuses['dodge'];
    }
    addLog(`${target.name || 'Player'} dodged the attack!`, 'info');
    return;
  }

  // Apply Power modifier
  const powerStacks = target === combatState.player ? 0 : (target.statuses['power'] || 0);
  // Power affects outgoing damage, not incoming - skip for now

  // Curl Up: gain block AFTER taking damage (first hit each turn, enemies only, not self-damage)
  // Flag is set here so we know to apply it post-damage
  const curlUpPending = target !== combatState.player && target.statuses
      && target.statuses['curl_up'] > 0 && !target.curlUpTriggeredThisTurn
      && !addons.includes('self');
  if (curlUpPending) {
    target.curlUpTriggeredThisTurn = true; // mark now so re-entrant hits don't double-trigger
  }

  // Check Stagger — if this single hit is ≥ X% of the target's max HP, apply Stun
  if (target !== combatState.player && target.staggerThreshold && target.staggerThreshold > 0) {
    if (dmg >= target.staggerThreshold * target.maxHealth) {
      target.statuses['stun'] = 1; // Stun is non-stackable
      addLog(`${target.name} is staggered by the heavy hit!`, 'warning');
    }
  }

  // Check Brace (reduce incoming damage by 1 per stack, minimum 1 total)
  const braceStacks = target.statuses['brace'] || 0;
  if (braceStacks > 0) {
    dmg = Math.max(1, dmg - braceStacks);
  }

  // Intangible: reduce all incoming damage to 1
  if (target.statuses && target.statuses['intangible']) {
    dmg = 1;
  }

  // Apply block first
  let remainingDamage = dmg;
  if (target.block > 0) {
    const blocked = Math.min(target.block, remainingDamage);
    target.block -= blocked;
    remainingDamage -= blocked;
    addLog(`${blocked} damage blocked`, 'info');
  }

  // Enemy Thorns — fires on hit (regardless of how much block absorbed), not just on health loss.
  // Routes back through dealDamageToPlayer so player's block can absorb it.
  // Only melee hits (not self-damage, not ranged).
  const _thornsRanged = addons.some(a => a.toLowerCase() === 'ranged');
  if (target !== combatState.player && target.statuses['thorns'] && !addons.includes('self') && !_thornsRanged) {
    dealDamageToPlayer(target.statuses['thorns'], ['self'], null);
    addLog(`Thorns: ${target.statuses['thorns']} damage reflected!`, 'warning');
  }

  // Bleed Thorns — enemy takes a melee hit, player (attacker) gains bleed
  if (target !== combatState.player && target.statuses['bleed_thorns'] && !addons.includes('self') && !_thornsRanged) {
    const bleedStacks = target.statuses['bleed_thorns'];
    combatState.player.statuses['bleed'] = (combatState.player.statuses['bleed'] || 0) + bleedStacks;
    addLog(`Bleed Thorns: you gained ${bleedStacks} Bleed!`, 'warning');
  }

  // Deal remaining damage to health
  if (remainingDamage > 0) {
    // Buffer (Slay the Spire style): only triggers when target would lose health, not on blocked hits
    if (target.statuses['buffer'] && target.statuses['buffer'] > 0 && !addons.includes('self')) {
      target.statuses['buffer']--;
      if (target.statuses['buffer'] <= 0) delete target.statuses['buffer'];
      addLog(`${target.name || 'Player'}'s Buffer absorbed the health loss!`, 'success');
      return;
    }

    target.health -= remainingDamage;
    addLog(`${target.name || 'Player'} took ${remainingDamage} damage`, 'danger');

    // Lifesteal: heal player equal to unblocked damage dealt to enemies
    if (target !== combatState.player && combatState._lifestealActive) {
      healTarget(combatState.player, remainingDamage);
      addLog(`Lifesteal: healed ${remainingDamage} HP`, 'success');
    }

    // Plated Armor: lose 1 stack when taking unblocked damage
    if (target.statuses && target.statuses['plated_armor']) {
      target.statuses['plated_armor']--;
      if (target.statuses['plated_armor'] <= 0) delete target.statuses['plated_armor'];
    }

    // Pigment Rich — hitting this enemy adds a random pigment card to the player's hand
    if (target !== combatState.player && target.statuses['pigment_rich']) {
      addPigmentCardToHand();
    }

    // Check Shifting: loses Power equal to damage taken; Shackled so it regains that Power end-of-turn
    if (target.statuses['shifting']) {
      const loss = remainingDamage;
      target.statuses['power'] = (target.statuses['power'] || 0) - loss;
      target.statuses['shackled'] = (target.statuses['shackled'] || 0) + loss;
    }

    // Envenom: when player deals unblocked attack damage to an enemy, apply X Poison
    if (target !== combatState.player && !addons.includes('self') && combatState.player.statuses['envenom']) {
      const poisonAmt = combatState.player.statuses['envenom'];
      target.statuses['poison'] = (target.statuses['poison'] || 0) + poisonAmt;
      addLog(`Envenom: +${poisonAmt} Poison!`, 'warning');
    }

    // Check Formless
    if (target.statuses['formless']) {
      rollEnemyIntent(target);
      addLog(`${target.name} rerolled intent due to Formless`, 'info');
    }

    // Soul Link — propagate health loss to all other soul-linked units
    if (target.statuses['soul_link'] && !combatState._soulLinkPropagating) {
      combatState._soulLinkPropagating = true;
      combatState.enemies.forEach(e => {
        if (e !== target && e.health > 0 && e.statuses['soul_link']) {
          dealDamage(e, remainingDamage, ['self']);
        }
      });
      if (target !== combatState.player && combatState.player.statuses['soul_link']) {
        dealDamageToPlayer(remainingDamage, ['self'], null);
      }
      combatState._soulLinkPropagating = false;
    }

    // Curl Up: gain block after receiving this hit (reactive block, doesn't absorb the triggering hit)
    if (curlUpPending) {
      const curlAmt = target.statuses['curl_up'];
      addBlock(target, curlAmt);
      addLog(`${target.name} curled up! Gained ${curlAmt} Block`, 'info');
    }

    // Trigger on-death ability for enemies that just died
    if (target !== combatState.player && target.health <= 0) {
      onEnemyDefeated(target);
    }

    // Skinning Homunculus reactive: "When another ally takes Melee Dmg, Add 1 Frail Overload to Intent"
    // Only fires on non-ranged, non-self player attacks against enemies
    if (target !== combatState.player && !addons.includes('self') && !addons.includes('Ranged')) {
      combatState.enemies.forEach(e => {
        if (e !== target && e.health > 0 &&
            /when another ally takes melee dmg/i.test(e.ability || '')) {
          if (!e.currentIntent) e.currentIntent = [];
          e.currentIntent.push({
            faceIndex: -1,
            face: {
              isBlank: false,
              raw: '1 Enfeebled Overload (reaction)',
              effects: [{
                raw: '1 Enfeebled',
                value: 1,
                move: 'Inflict',
                addons: ['Overload'],
                target: 'Enfeebled'
              }]
            },
            resolved: false
          });
          addLog(`${e.name} reacts: +1 Enfeebled Overload added to intent!`, 'warning');
        }
      });
    }
  }

  // Dead Eye: track consecutive hits on same target — update streak after hit confirmed
  if (target !== combatState.player && !addons.includes('self')) {
    const _deInv = typeof window.inventory !== 'undefined' ? window.inventory : [];
    if (_deInv.some(i => i.name === 'Dead Eye')) {
      const targetId = target.id || target.name;
      if (combatState._deadEyeTarget !== targetId) combatState._deadEyeBonus = 0;
      combatState._deadEyeTarget = targetId;
      combatState._deadEyeBonus = (combatState._deadEyeBonus || 0) + 1;
    }
  }

  // Update global health if player
  if (target === combatState.player) {
    window.health = target.health;
  }
}

/**
 * Add block to a target
 * @param {Object} target - Target entity
 * @param {number} amount - Block amount
 */
function addBlock(target, amount) {
  const base = (typeof amount === 'number' && !isNaN(amount)) ? amount : 0;
  if (base <= 0) return;
  // Apply Defense status bonus (Footwork etc.)
  const defense = (target.statuses && target.statuses['defense']) ? target.statuses['defense'] : 0;
  let blockAmount = Math.max(0, base + defense);
  // Frail (STS): reduces block gained by 25%
  if (target.statuses && target.statuses['frail']) {
    blockAmount = Math.floor(blockAmount * 0.75);
  }
  if (blockAmount <= 0) return;
  target.block = (target.block || 0) + blockAmount;
  addLog(`${target.name || 'Player'} gained ${blockAmount} block`, 'info');

  // Juggernaut: when player gains block, deal damage to a random enemy
  if (target === combatState.player && combatState.player.statuses && combatState.player.statuses['juggernaut']) {
    const jugDmg = combatState.player.statuses['juggernaut'];
    const jugLive = combatState.enemies.filter(e => e.health > 0);
    if (jugLive.length > 0) {
      const jugTarget = jugLive[Math.floor(Math.random() * jugLive.length)];
      dealDamage(jugTarget, jugDmg, ['melee']);
      addLog(`Juggernaut: ${jugDmg} Melee dmg to ${jugTarget.name}!`, 'success');
    }
  }
}

/**
 * Add a "Separate" status instance (stores as array, each entry is a distinct instance).
 * Used for Next Turn Block / Draw / Energy which don't stack but create separate instances.
 */
function addSeparateStatus(target, key, amount) {
  if (!Array.isArray(target.statuses[key])) {
    target.statuses[key] = target.statuses[key] ? [target.statuses[key]] : [];
  }
  target.statuses[key].push(amount);
}

/**
 * Compute the effective energy cost of a card, accounting for dynamic-cost effects.
 * Returns 'X' or 'No' for special cost types, or a plain number otherwise.
 */
function getEffectiveCost(card) {
  if (!card) return 0;
  if (card._freeCost) return 0;
  const raw = card.cost;
  if (raw === 'X' || raw === 'No') return raw;
  let cost = parseInt(raw) || 0;
  const desc = card.description || '';
  if (/Costs 1 less Energy for each Discarded Card this turn/i.test(desc)) {
    cost = Math.max(0, cost - ((combatState && combatState._discardsThisTurn) || 0));
  }
  if (/Costs 1 more Energy for each time you've lost Health this combat/i.test(desc)) {
    cost = cost + ((combatState && combatState._playerHealthLossTimes) || 0);
  }
  // Blood for Blood: costs 1 less per health loss event
  if (/Costs 1 less Energy for each time you lost Health this combat/i.test(desc)) {
    cost = Math.max(0, cost - ((combatState && combatState._playerHealthLossTimes) || 0));
  }
  // Grand Finale: can only be played with an empty draw pile
  if (/Can only be played if there are no cards in your draw pile/i.test(desc)) {
    if (combatState && combatState.drawPile && combatState.drawPile.length > 0) {
      return 'No';
    }
  }
  // Clash: unplayable if any card in hand is not an Attack
  if (/Can only be played if every Card in your Hand is an Attack/i.test(desc)) {
    const hand = (combatState && combatState.hand) || [];
    if (hand.some(c => (c.type || '').toLowerCase() !== 'attack')) return 'No';
  }
  // Corruption: Skills cost 0
  if (combatState && combatState.player && combatState.player.statuses && combatState.player.statuses['corruption']) {
    if ((card.type || '').toLowerCase() === 'skill') cost = 0;
  }
  // Fear: non-Skill cards cost +1 (Skills reduce Fear, all others cost more)
  if (combatState && combatState.player && combatState.player.statuses && combatState.player.statuses['fear']) {
    if ((card.type || '').toLowerCase() !== 'skill' && typeof cost === 'number') cost += 1;
  }
  return cost;
}

/**
 * Heal a target
 * @param {Object} target - Target entity
 * @param {number} amount - Heal amount
 */
function healTarget(target, amount) {
  // Validate inputs
  const healAmount = (typeof amount === 'number' && !isNaN(amount)) ? amount : 0;
  if (healAmount <= 0) return;

  // Ensure target has valid health values
  const currentHealth = (typeof target.health === 'number' && !isNaN(target.health)) ? target.health : 0;
  const maxHealth = (typeof target.maxHealth === 'number' && !isNaN(target.maxHealth)) ? target.maxHealth : currentHealth;

  const healed = Math.min(healAmount, maxHealth - currentHealth);
  target.health = currentHealth + healed;
  addLog(`${target.name || 'Player'} healed ${healed}`, 'success');

  if (target === combatState.player) {
    window.health = target.health;
  }
}

/**
 * Reduce player health via health-loss effects (Combust, Hemokinesis, etc.).
 * Goes through block before affecting health. Respects Intangible.
 * Counts toward _playerHealthLossTimes only when actual health is lost.
 * Does NOT trigger take-damage-only effects (Thorns, Prayer Card, etc).
 */
function loseHealth(amount) {
  const player = combatState.player;
  let hp = amount;
  if (player.statuses && player.statuses['intangible']) hp = 1;
  if (hp <= 0) return;
  // Consume block first
  const blocked = Math.min(hp, player.block || 0);
  if (blocked > 0) {
    player.block -= blocked;
    hp -= blocked;
  }
  if (hp <= 0) return;
  player.health -= hp;
  window.health = player.health;
  combatState._playerHealthLossTimes = (combatState._playerHealthLossTimes || 0) + 1;
  addLog(`Lost ${hp} Health`, 'danger');
  // Rupture: gain power whenever health is lost from a card
  if (combatState._inCardResolution && player.statuses && player.statuses['rupture_power']) {
    const gain = player.statuses['rupture_power'];
    player.statuses['power'] = (player.statuses['power'] || 0) + gain;
    addLog(`Rupture: +${gain} Power`, 'success');
  }
}

/**
 * Cleanse debuffs from a target
 * @param {Object} target - Target entity
 * @param {number} stacks - Stacks to remove per debuff
 */
function cleanseDebuffs(target, stacks) {
  const debuffs = ['burn', 'poison', 'oiled', 'frail', 'enfeebled', 'ruptured', 'confused', 'fading'];

  debuffs.forEach(debuff => {
    if (target.statuses[debuff]) {
      target.statuses[debuff] = Math.max(0, target.statuses[debuff] - stacks);
      if (target.statuses[debuff] <= 0) {
        delete target.statuses[debuff];
      }
    }
  });

  addLog(`Cleansed ${stacks} stacks of debuffs`, 'success');
}

/**
 * Process spell effect (similar to die effect but with spell-specific handling)
 * @param {Object} effect - Effect data
 * @param {Object} spell - Spell data
 * @param {Object} targets - Targets
 */
function processSpellEffect(effect, spell, targets) {
  // "Self/Ally gains X Status" — apply a status to player or chosen ally (e.g. Bind: 1 Buffer)
  if (effect.move && effect.move.toLowerCase() === 'self/ally') {
    const addons = effect.addons || [];
    const numIdx = addons.findIndex(a => !isNaN(parseInt(a)));
    const amount = numIdx !== -1 ? parseInt(addons[numIdx]) : 1;
    const statusName = addons.slice(numIdx + 1).join('_').toLowerCase();
    if (statusName) {
      const applyTo = targets.allyId
        ? combatState.allies.find(a => a.id === targets.allyId)
        : combatState.player;
      if (applyTo) {
        applyStatus(applyTo, statusName, amount);
        addLog(`Gained ${amount} ${statusName}`, 'success');
      }
    }
    return;
  }

  // Standard effect processing
  processEffect(effect, null, targets);
}

// ============== COMPLEX ENEMY MECHANICS ==============

/**
 * Remove a random pigment (isStatusCard) card from any combat pile.
 * Returns true if one was found and removed.
 */
function consumeRandomPigmentCard() {
  const piles = [
    { list: combatState.hand,        name: 'hand'    },
    { list: combatState.drawPile,    name: 'draw'    },
    { list: combatState.discardPile, name: 'discard' },
  ];
  const candidates = [];
  piles.forEach(({ list, name }) => {
    list.forEach((card, idx) => {
      if (card.isStatusCard) candidates.push({ list, idx, card, name });
    });
  });
  if (candidates.length === 0) return false;
  const pick = candidates[Math.floor(Math.random() * candidates.length)];
  pick.list.splice(pick.idx, 1);
  addLog(`${pick.card.name} was consumed!`, 'info');
  return true;
}

/**
 * Spawn a named enemy at a given combat position, replacing whoever is there.
 * If the slot is already alive, the new enemy is pushed to the end instead.
 */
function spawnEnemyAtSlot(enemyName, position) {
  if (typeof ENEMIES_DATA === 'undefined') {
    addLog(`Cannot spawn ${enemyName}: ENEMIES_DATA not loaded`, 'warning');
    return;
  }
  const template = ENEMIES_DATA.find(e => e.name.toLowerCase() === enemyName.toLowerCase());
  if (!template) {
    addLog(`Cannot spawn ${enemyName}: not found`, 'warning');
    return;
  }

  let hp;
  if (template.hpMin !== undefined && template.hpMax !== undefined) {
    hp = Math.floor(Math.random() * (template.hpMax - template.hpMin + 1)) + template.hpMin;
  } else {
    hp = template.hp || 10;
  }

  const isOrdered = /Turn \d+:/i.test(template.pattern || '');
  const newEnemy = {
    id: `enemy_${position}_spawn_${Date.now()}`,
    name: template.name,
    type: template.type,
    difficulty: template.difficulty,
    weight: template.weight,
    health: hp,
    maxHealth: hp,
    block: 0,
    statuses: parseStartingAbilities(template.ability),
    ability: template.ability,
    pattern: template.pattern || '',
    patternType: isOrdered ? 'ordered' : 'random',
    patternTurns: isOrdered ? parseOrderedPattern(template.pattern) : null,
    patternTurnIndex: 0,
    game: template.game,
    location: template.location,
    dice: template.dice,
    currentIntent: null,
    imageUrl: template.imageUrl,
    position: position,
    staggerThreshold: parseStaggerThreshold(template.ability),
    rolledFaces: new Set(),
    curlUpTriggeredThisTurn: false,
    splitAbility: parseSplitAbility(template.ability)
  };
  resolveDeterminedValues(newEnemy);

  // Mark as just spawned: shows Unknown intent and skips action on spawn turn
  newEnemy.justSpawned = true;
  newEnemy.currentIntent = [{
    faceIndex: 0,
    face: { isBlank: true, effects: [], raw: 'Unknown' },
    resolved: false
  }];

  // Replace dead enemy at this position; otherwise append
  const idx = combatState.enemies.findIndex(e => e.position === position && e.health <= 0);
  if (idx !== -1) {
    combatState.enemies[idx] = newEnemy;
  } else {
    newEnemy.position = combatState.enemies.length;
    combatState.enemies.push(newEnemy);
  }

  addLog(`${template.name} spawned!`, 'warning');
  if (typeof window.updateCombatDisplay === 'function') window.updateCombatDisplay();
}

/**
 * Spawn a split copy of an enemy with a specific HP value (used by Split ability).
 * @param {string} enemyName - Template name to look up
 * @param {number} inheritedHp - HP to give the spawn (≤ template max)
 */
function spawnSplitEnemy(enemyName, inheritedHp) {
  if (typeof ENEMIES_DATA === 'undefined') return;
  const template = ENEMIES_DATA.find(e => e.name.toLowerCase() === enemyName.toLowerCase());
  if (!template) {
    addLog(`Split: cannot find template "${enemyName}"`, 'warning');
    return;
  }

  const isOrdered = /Turn \d+:/i.test(template.pattern || '');
  const spawnHp = Math.max(1, inheritedHp);
  const position = combatState.enemies.length;
  const newEnemy = {
    id: `enemy_split_${position}_${Date.now()}`,
    name: template.name,
    type: template.type,
    difficulty: template.difficulty,
    weight: template.weight,
    health: spawnHp,
    maxHealth: template.hpMax || template.hp || spawnHp,
    block: 0,
    statuses: parseStartingAbilities(template.ability),
    ability: template.ability,
    pattern: template.pattern || '',
    patternType: isOrdered ? 'ordered' : 'random',
    patternTurns: isOrdered ? parseOrderedPattern(template.pattern) : null,
    patternTurnIndex: 0,
    game: template.game,
    location: template.location,
    dice: template.dice,
    currentIntent: null,
    imageUrl: template.imageUrl,
    position,
    staggerThreshold: parseStaggerThreshold(template.ability),
    rolledFaces: new Set(),
    curlUpTriggeredThisTurn: false,
    splitAbility: parseSplitAbility(template.ability)
  };
  resolveDeterminedValues(newEnemy);

  // Mark as just spawned: shows Unknown intent and skips action on spawn turn
  newEnemy.justSpawned = true;
  newEnemy.currentIntent = [{
    faceIndex: 0,
    face: { isBlank: true, effects: [], raw: 'Unknown' },
    resolved: false
  }];

  combatState.enemies.push(newEnemy);
  addLog(`${template.name} (${spawnHp} HP) emerges from the split!`, 'warning');
  if (typeof window.updateCombatDisplay === 'function') window.updateCombatDisplay();
}

/**
 * Execute the "When Defeated, <clause>" portion of an enemy's ability.
 * Recursive: handles probability splits before dispatching specific effects.
 */
function executeWhenDefeatedClause(enemy, clause) {
  const text = clause.trim();

  // Probability split: "60% Spawn Pacer / 40% Spawn Gusher"
  if (text.includes('%') && text.includes('/')) {
    const parts = text.split('/').map(s => s.trim());
    const weighted = [];
    for (const p of parts) {
      const m = p.match(/^(\d+(?:\.\d+)?)%\s*(.*)/);
      if (m) weighted.push({ weight: parseFloat(m[1]), text: m[2].trim() });
    }
    if (weighted.length > 0) {
      const total = weighted.reduce((s, o) => s + o.weight, 0);
      let roll = Math.random() * total;
      for (const o of weighted) {
        roll -= o.weight;
        if (roll <= 0) { executeWhenDefeatedClause(enemy, o.text); return; }
      }
      executeWhenDefeatedClause(enemy, weighted[weighted.length - 1].text);
      return;
    }
  }

  // Single probability: "50% chance to Spawn Mung"
  const chancePct = text.match(/^(\d+(?:\.\d+)?)%\s*(?:chance\s+to\s+)?(.+)/i);
  if (chancePct) {
    if (Math.random() * 100 < parseFloat(chancePct[1])) {
      executeWhenDefeatedClause(enemy, chancePct[2].trim());
    }
    return;
  }

  // Spawn <EnemyName>
  const spawnM = text.match(/^Spawn\s+(.+)/i);
  if (spawnM) {
    spawnEnemyAtSlot(spawnM[1].trim(), enemy.position);
    return;
  }

  // N Dmg to (its) adjacent allies
  const adjDmgM = text.match(/^(\d+)\s+Dmg\s+to\s+(?:it[''s]*\s+)?adjacent\s+allies?/i);
  if (adjDmgM) {
    const dmg = parseInt(adjDmgM[1]);
    const pos = enemy.position;
    combatState.enemies.forEach(e => {
      if (e !== enemy && e.health > 0 && Math.abs(e.position - pos) === 1) {
        e.health -= dmg;
        addLog(`${e.name} took ${dmg} damage from ${enemy.name}'s death!`, 'danger');
      }
    });
    return;
  }

  // Strength Save DC or take X Dmg
  const strSaveM = text.match(/^Strength\s+Save\s+(\d+)\s+or\s+take\s+(\d+)\s+Dmg/i);
  if (strSaveM) {
    const dc  = parseInt(strSaveM[1]);
    const dmg = parseInt(strSaveM[2]);
    const roll   = Math.floor(Math.random() * 20) + 1;
    const strMod = combatState.player.bonuses?.strength || 0;
    const total  = roll + strMod;
    addLog(`Strength Save DC${dc}: rolled ${roll} + ${strMod} mod = ${total}`, 'info');
    if (total < dc) {
      combatState.player.health -= dmg;
      window.health = combatState.player.health;
      addLog(`Failed save! Took ${dmg} damage.`, 'danger');
    } else {
      addLog('Passed Strength Save!', 'success');
    }
    return;
  }

  addLog(`${enemy.name} death effect unhandled: ${text}`, 'info');
}

/**
 * Trigger an enemy's on-death ability clause (called once per enemy death).
 */
function onEnemyDefeated(enemy) {
  if (enemy.onDeathTriggered) return;
  enemy.onDeathTriggered = true;

  const inv = typeof window.inventory !== 'undefined' ? window.inventory : [];

  // Metal Plate: when you kill an enemy, gain +1 Brace
  if (inv.some(i => i.name === 'Metal Plate')) {
    combatState.player.statuses['brace'] = (combatState.player.statuses['brace'] || 0) + 1;
    addLog('Metal Plate: +1 Brace!', 'success');
  }

  // Gremlin Horn: when an enemy dies, gain +1 Energy and draw 1 card
  if (inv.some(i => i.name === 'Gremlin Horn')) {
    combatState.player.energy++;
    drawCards(1);
    addLog('Gremlin Horn: +1 Energy, draw 1!', 'success');
  }

  // Charm of the Vampire: 50% chance to heal +3 HP per copy on enemy defeat
  const vampireCount = inv.filter(i => i.name === 'Charm of the Vampire').length;
  if (vampireCount > 0 && Math.random() < 0.5) {
    const healAmt = 3 * vampireCount;
    if (typeof health !== 'undefined' && typeof maxHealth !== 'undefined') {
      health = Math.min(maxHealth, health + healAmt);
      if (typeof gameState !== 'undefined') gameState.health = health;
      if (typeof updateTopBar === 'function') updateTopBar();
    }
    addLog(`Charm of the Vampire: +${healAmt} Health!`, 'success');
    if (typeof createNotification === 'function') setTimeout(() => createNotification(`Charm of the Vampire: +${healAmt} HP!`, '#2ecc71', '🧛'), 100);
  }

  // Corpse Explosion: on death, deal X * maxHealth to all other living enemies
  if (enemy.statuses && enemy.statuses['corpse_explosion']) {
    const mult = enemy.statuses['corpse_explosion'];
    const explodeDmg = Math.round(mult * (enemy.maxHealth || 0));
    if (explodeDmg > 0) {
      combatState.enemies.filter(e => e !== enemy && e.health > 0).forEach(e => {
        dealDamage(e, explodeDmg, ['self']);
      });
      addLog(`Corpse Explosion: ${explodeDmg} damage to all other enemies!`, 'danger');
    }
  }

  if (!enemy.ability) return;
  const m = enemy.ability.match(/When Defeated,?\s*(.+)/i);
  if (!m) return;
  addLog(`${enemy.name}: death trigger fires!`, 'warning');
  executeWhenDefeatedClause(enemy, m[1].trim());
}

// ============== TURN MANAGEMENT ==============

/**
 * Process player's start of turn
 */
function processPlayerStartOfTurn() {
  combatState.phase = 'player_action';

  // Process player status effects
  processStatusEffects(combatState.player, 'start');

  // Fire queued Future spell effects
  if (combatState.futureEffects && combatState.futureEffects.length > 0) {
    combatState.futureEffects.forEach(({ effect, spell, targets }) => {
      processSpellEffect(effect, spell, targets);
    });
    combatState.futureEffects = [];
  }

  // Reset cooldowns
  combatState.spellCooldowns = {};

  // Reset energy to base max
  combatState.player.energy = combatState.player.maxEnergy;

  // Ice Cream: add any carried-over energy from last turn (can exceed maxEnergy)
  if (combatState._iceCreamCarryOver > 0) {
    combatState.player.energy += combatState._iceCreamCarryOver;
    addLog(`Ice Cream: +${combatState._iceCreamCarryOver} bonus energy!`, 'success');
    combatState._iceCreamCarryOver = 0;
  }

  // Apply power_per_turn (Demon Form etc.)
  if (combatState.player.statuses['power_per_turn']) {
    const gain = combatState.player.statuses['power_per_turn'];
    combatState.player.statuses['power'] = (combatState.player.statuses['power'] || 0) + gain;
    addLog(`Gained ${gain} Power (Demon Form)`, 'success');
  }

  // Berserk: gain energy at start of each turn
  if (combatState.player.statuses['energy_per_turn']) {
    const gain = combatState.player.statuses['energy_per_turn'];
    combatState.player.energy += gain;
    addLog(`Berserk: +${gain} Energy`, 'success');
  }

  // Brutality: lose 1 HP and draw 1 card at start of each turn
  if (combatState.player.statuses['brutality']) {
    loseHealth(1);
    drawCards(1);
    addLog('Brutality: lost 1 HP, drew 1 card', 'warning');
  }

  // Noxious Fumes: inflict poison_per_turn to all enemies at start of turn
  if (combatState.player.statuses['poison_per_turn']) {
    const stacks = combatState.player.statuses['poison_per_turn'];
    combatState.enemies.filter(e => e.health > 0).forEach(e => {
      e.statuses['poison'] = (e.statuses['poison'] || 0) + stacks;
    });
    addLog(`Noxious Fumes: ${stacks} Poison to all enemies!`, 'warning');
  }

  // Clear block at start of player turn (unless Barricade or Blur)
  if (!combatState.player.statuses['barricade'] && !combatState.player.statuses['blur']) {
    if (combatState.player.block > 0) combatState.player.block = 0;
  } else if (combatState.player.statuses['blur'] > 0) {
    // Blur: preserve block this turn, then decay the Blur stack
    combatState.player.statuses['blur']--;
    if (combatState.player.statuses['blur'] <= 0) delete combatState.player.statuses['blur'];
    addLog('Blur: block preserved this turn!', 'success');
  }

  // Next Turn Block (Separate stacking — array of instances)
  if (combatState.player.statuses['next_turn_block']) {
    const instances = Array.isArray(combatState.player.statuses['next_turn_block'])
      ? combatState.player.statuses['next_turn_block']
      : [combatState.player.statuses['next_turn_block']];
    instances.forEach(amt => addBlock(combatState.player, amt));
    delete combatState.player.statuses['next_turn_block'];
    const total = instances.reduce((a, b) => a + b, 0);
    addLog(`Next Turn Block: +${total} Block!`, 'success');
  }

  // Next Turn Energy (Separate stacking — array of instances)
  if (combatState.player.statuses['next_turn_energy']) {
    const instances = Array.isArray(combatState.player.statuses['next_turn_energy'])
      ? combatState.player.statuses['next_turn_energy']
      : [combatState.player.statuses['next_turn_energy']];
    instances.forEach(amt => { combatState.player.energy += amt; });
    delete combatState.player.statuses['next_turn_energy'];
    const total = instances.reduce((a, b) => a + b, 0);
    addLog(`Next Turn Energy: +${total} Energy!`, 'success');
  }

  // Next Turn Draw (Separate stacking — array of instances)
  if (combatState.player.statuses['next_turn_draw']) {
    const instances = Array.isArray(combatState.player.statuses['next_turn_draw'])
      ? combatState.player.statuses['next_turn_draw']
      : [combatState.player.statuses['next_turn_draw']];
    delete combatState.player.statuses['next_turn_draw'];
    instances.forEach(amt => drawCards(amt));
    const total = instances.reduce((a, b) => a + b, 0);
    addLog(`Next Turn Draw: Drew ${total} card(s)!`, 'success');
  }

  // Reset discard-tracking flags for Sneaky Strike / Eviscerate etc.
  combatState._discardedThisTurn = false;
  combatState._discardsThisTurn = 0;

  // Infinite Blades: conjure Shiv(s) to hand at start of each turn
  if (combatState.player.statuses['shiv_per_turn']) {
    const shivCount = combatState.player.statuses['shiv_per_turn'];
    const shivTemplate = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.find(c => c.name === 'Shiv') : null;
    if (shivTemplate) {
      let conjured = 0;
      for (let i = 0; i < shivCount && combatState.hand.length < HAND_SIZE_LIMIT; i++) {
        combatState.hand.push({ ...shivTemplate, _uid: `shiv_ibl_${Date.now()}_${i}` });
        conjured++;
      }
      if (conjured > 0) addLog(`Infinite Blades: Conjured ${conjured} Shiv(s)`, 'success');
    }
  }

  // Tools of the Trade: draw 1, then discard 1 at start of each turn
  if (combatState.player.statuses['tools_of_trade']) {
    drawCards(1);
    if (combatState.hand.length > 0) {
      combatState._pendingCardPick = { action: 'discard', pile: 'hand', count: 1 };
    }
    addLog('Tools of the Trade: draw 1, discard 1', 'success');
  }

  // Wraith Form: lose 1 Defense at the start of each turn
  if (combatState.player.statuses['wraith_form']) {
    if (combatState.player.statuses['defense'] > 0) {
      combatState.player.statuses['defense']--;
      if (combatState.player.statuses['defense'] <= 0) delete combatState.player.statuses['defense'];
    }
    addLog('Wraith Form: lost 1 Defense', 'warning');
  }

  // Nightmare: conjure N copies of the chosen card to hand
  if (combatState._nightmareCard) {
    const nc = combatState._nightmareCard;
    const nc_count = combatState._nightmareCount || 3;
    delete combatState._nightmareCard;
    delete combatState._nightmareCount;
    for (let i = 0; i < nc_count && combatState.hand.length < HAND_SIZE_LIMIT; i++) {
      combatState.hand.push({ ...nc, _uid: `nightmare_${Date.now()}_${i}` });
    }
    addLog(`Nightmare: conjured ${nc_count}x ${nc.name}!`, 'success');
  }

  // Horn Cleat: +14 Block at the start of the second turn
  if (combatState._hornCleatPending && combatState.turn === 2) {
    addBlock(combatState.player, 14);
    addLog('Horn Cleat: +14 Block!', 'success');
    combatState._hornCleatPending = false;
  }

  // Draw cards for this turn
  if (combatState.drawPile !== undefined) {
    let drawCount = BASE_DRAW_PER_TURN;
    // Ambush/Ambushed: adjust first-turn draw count
    if (combatState.turn === 1 && typeof gameState !== 'undefined') {
      if (gameState.pendingAmbush) {
        drawCount += 2;
        addLog('Ambush! Drew 2 extra cards.', 'success');
        gameState.pendingAmbush = false;
      } else if (gameState.pendingAmbushed) {
        drawCount = Math.max(0, drawCount - 2);
        addLog('Ambushed! Drew 2 fewer cards.', 'danger');
        gameState.pendingAmbushed = false;
      }
    }
    drawCards(drawCount);
  }

  // Machine Learning: draw +1 card per stack at start of each turn
  if (Array.isArray(combatState.player.statuses['machine_learning']) && combatState.player.statuses['machine_learning'].length > 0) {
    const mlCount = combatState.player.statuses['machine_learning'].length;
    drawCards(mlCount);
    addLog(`Machine Learning: drew ${mlCount} extra card${mlCount !== 1 ? 's' : ''}!`, 'success');
  }

  // Well-Laid Plans: clear old retain flags, then let player pick which cards to retain
  if (combatState.player.statuses['well_laid_plans'] > 0 && combatState.hand.length > 0) {
    for (const hc of combatState.hand) delete hc._retain;
    combatState._pendingRetainPick = { count: combatState.player.statuses['well_laid_plans'] };
  }

  // Check for Horn Cleat on turn 2 (stacks: +5 Block per copy)
  if (combatState.turn === 2 && typeof inventory !== 'undefined') {
    const hornCleatCount = inventory.filter(item => item.name === 'Horn Cleat').length;
    if (hornCleatCount > 0) {
      const totalBlock = 5 * hornCleatCount;
      addBlock(combatState.player, totalBlock);
      addLog(`Horn Cleat${hornCleatCount > 1 ? ` x${hornCleatCount}` : ''} grants +${totalBlock} Block!`, 'success');
    }
  }

  if (typeof inventory !== 'undefined') {
    // Captain's Wheel: +18 Block at the start of turn 3
    if (combatState.turn === 3) {
      const captainsWheelCount = inventory.filter(i => i.name === "Captain's Wheel").reduce((n, i) => n + (i.quantity || 1), 0);
      if (captainsWheelCount > 0) {
        addBlock(combatState.player, 18 * captainsWheelCount);
        addLog(`Captain's Wheel: +${18 * captainsWheelCount} Block!`, 'success');
      }
    }

    // Happy Flower: every 3 turns, gain +1 Energy
    if (combatState.turn > 1 && combatState.turn % 3 === 0) {
      const happyFlowerCount = inventory.filter(i => i.name === 'Happy Flower').reduce((n, i) => n + (i.quantity || 1), 0);
      if (happyFlowerCount > 0) {
        combatState.player.energy += happyFlowerCount;
        addLog(`Happy Flower: +${happyFlowerCount} Energy!`, 'success');
      }
    }
  }

  // Reset per-turn attack counter for incremental items
  if (combatState.incrementals) {
    combatState.incrementals.attacksThisTurn = 0;
  }

  addLog(`--- Turn ${combatState.turn} ---`, 'info');
}

/**
 * End the player's turn
 * @returns {Object} Result
 */
function endTurn() {
  if (!combatState || combatState.phase !== 'player_action') {
    return { success: false, error: 'Cannot end turn now' };
  }

  combatState.phase = 'end_turn';

  // Pending dice expire at end of turn
  combatState.pendingDice = [];

  // Ice Cream: carry over leftover energy to next turn (player can exceed maxEnergy)
  const iceCreamCount = typeof inventory !== 'undefined'
    ? inventory.filter(i => i.name === 'Ice Cream').reduce((n, i) => n + (i.quantity || 1), 0)
    : 0;
  if (iceCreamCount > 0 && combatState.player.energy > 0) {
    combatState._iceCreamCarryOver = (combatState._iceCreamCarryOver || 0) + combatState.player.energy;
    addLog(`Ice Cream: ${combatState.player.energy} energy carried over!`, 'success');
  }

  // Clear Choked status from all enemies at end of player turn
  combatState.enemies.forEach(e => {
    if (e.statuses['choked']) delete e.statuses['choked'];
  });

  // Well-Laid Plans: player picks which cards to retain — handled via start-of-turn picker

  // Curse and Status card end-of-turn effects (fire while cards are still in hand)
  if (combatState.hand) {
    const handSnapshot = [...combatState.hand];
    for (const card of handSnapshot) {
      const isCardCurse = card.isCurse || (card.type || '').toLowerCase() === 'curse';
      if (!isCardCurse && !card.isStatusCard) continue;

      // Status card end-of-turn effects (e.g. Burn: take N Dmg)
      if (card.isStatusCard) {
        const burnStatusM = card.description && card.description.match(/At the end of your turn, take (\d+) Dmg/i);
        if (burnStatusM) {
          const burnDmg = parseInt(burnStatusM[1]);
          dealDamageToPlayer(burnDmg, ['self'], null);
          addLog(`${card.name}: took ${burnDmg} damage!`, 'danger');
        }
        continue;
      }
      const cdesc = (card.description || '').toLowerCase();
      // Decay: deals 2 Dmg to player
      if (/deals \d+ dmg to you/i.test(card.description)) {
        const dmgMatch = card.description.match(/deals (\d+) Dmg to you/i);
        const dmgAmt = dmgMatch ? parseInt(dmgMatch[1]) : 2;
        dealDamageToPlayer(dmgAmt, ['self'], null);
        addLog(`Decay: took ${dmgAmt} damage!`, 'danger');
      }
      // Doubt: gain 1 Weak
      if (/gain \d+ weak/i.test(card.description)) {
        const wkMatch = card.description.match(/Gain (\d+) Weak/i);
        combatState.player.statuses['weak'] = (combatState.player.statuses['weak'] || 0) + (wkMatch ? parseInt(wkMatch[1]) : 1);
        addLog(`Doubt: Gained 1 Weak`, 'warning');
      }
      // Shame: gain 1 Frail
      if (/gain \d+ frail/i.test(card.description)) {
        const frMatch = card.description.match(/Gain (\d+) Frail/i);
        combatState.player.statuses['frail'] = (combatState.player.statuses['frail'] || 0) + (frMatch ? parseInt(frMatch[1]) : 1);
        addLog(`Shame: Gained 1 Frail`, 'warning');
      }
      // Regret: lose 1 Health for each card in hand
      if (/lose \d+ health for each card in hand/i.test(card.description)) {
        const regretDmg = combatState.hand.length;
        if (regretDmg > 0) {
          loseHealth(regretDmg);
          addLog(`Regret: Lost ${regretDmg} Health (${regretDmg} cards in hand)`, 'danger');
        }
      }
      // Punctured Eye / Gain N Blind
      if (/gain \d+ blind/i.test(card.description)) {
        const blindMatch = card.description.match(/Gain (\d+) Blind/i);
        const blindAmt = blindMatch ? parseInt(blindMatch[1]) : 1;
        combatState.player.statuses['blind'] = (combatState.player.statuses['blind'] || 0) + blindAmt;
        addLog(`${card.name}: Gained ${blindAmt} Blind`, 'warning');
      }
    }
  }

  // Discard hand (Ethereal → exhaust; Sly → trigger; Retained → keep; others → discard)
  if (combatState.hand) {
    const kept = [];
    for (const card of [...combatState.hand]) {
      if (card._retain) { kept.push(card); continue; }
      const descLower = (card.description || '').toLowerCase();
      if (descLower.includes('ethereal')) {
        combatState.exhaustPile.push(card);
        addLog(`${card.name} exhausted (Ethereal)`, 'info');
        onCardExhausted(card);
      } else if (descLower.includes('sly')) {
        addLog(`${card.name}: Sly — triggered on discard!`, 'success');
        resolveCardEffect(card, null);
        combatState.discardPile.push(card);
      } else {
        combatState.discardPile.push(card);
      }
    }
    combatState.hand = kept;
    combatState.selectedCardIndex = null;
  }

  // Cap mana at max
  if (combatState.player.mana > combatState.player.maxMana) {
    combatState.player.mana = combatState.player.maxMana;
  }

  // Stone Calendar: at the end of turn 7, deal 52 damage to all enemies
  if (combatState.turn === 7 && typeof inventory !== 'undefined') {
    const hasStoneCalendar = inventory.some(i => i.name === 'Stone Calendar');
    if (hasStoneCalendar) {
      combatState.enemies.filter(e => e.health > 0).forEach(e => dealDamage(e, 52, ['self']));
      addLog('Stone Calendar: 52 damage to all enemies!', 'success');
    }
  }

  // Process enemy start-of-turn status effects (burn/poison tick BEFORE enemies act)
  combatState.enemies.forEach(enemy => {
    if (enemy.health > 0) {
      processStatusEffects(enemy, 'start');
    }
  });

  // Check for victory from burn/poison kills before enemies act
  if (combatState.enemies.every(e => e.health <= 0)) {
    combatState.phase = 'victory';
    addLog('Victory!', 'success');
    return { success: true, phase: 'victory' };
  }

  // Decay player statuses at end of player's turn (BEFORE enemy actions so that statuses
  // the enemy inflicts this turn persist for the player's full next turn)
  processStatusEffects(combatState.player, 'end');

  // Execute enemy actions
  executeEnemyActions();

  // Check for player defeat
  if (combatState.player.health <= 0) {
    combatState.phase = 'defeat';
    addLog('Defeated!', 'danger');
    return { success: true, phase: 'defeat' };
  }

  // Check for victory
  const allDead = combatState.enemies.every(e => e.health <= 0);
  if (allDead) {
    combatState.phase = 'victory';
    addLog('Victory!', 'success');
    return { success: true, phase: 'victory' };
  }

  // Process enemy end-of-turn status effects (decay statuses AFTER they've acted)
  combatState.enemies.forEach(enemy => {
    if (enemy.health > 0) {
      processStatusEffects(enemy, 'end');
    }
  });

  // Prayer Beads: clear the temporary brace gained THIS turn now that all enemies have acted
  {
    const ps = combatState.player.statuses;
    if (ps['brace_temp'] && ps['brace_temp'] > 0) {
      ps['brace'] = Math.max(0, (ps['brace'] || 0) - ps['brace_temp']);
      if (ps['brace'] <= 0) delete ps['brace'];
      delete ps['brace_temp'];
    }
  }

  // Reset block (unless Barricade)
  if (!combatState.player.statuses['barricade']) {
    combatState.player.block = 0;
  } else {
    combatState.player.block = Math.floor(combatState.player.block / 2);
  }

  // Leeches: drain health from all enemies leeched by the player, heal the player
  let playerLeechHeal = 0;
  combatState.enemies.forEach(enemy => {
    if (enemy.health > 0 && enemy.statuses['leeches'] && enemy.statuses['leeches_owner'] === 'player') {
      const drain = enemy.statuses['leeches'];
      enemy.health = Math.max(0, enemy.health - drain);
      playerLeechHeal += drain;
      if (enemy.health <= 0) onEnemyDefeated(enemy);
    }
  });
  if (playerLeechHeal > 0) {
    combatState.player.health = Math.min(combatState.player.maxHealth, combatState.player.health + playerLeechHeal);
    window.health = combatState.player.health;
    addLog(`Leeches drained ${playerLeechHeal} health → healed player`, 'success');
  }

  // Start new turn
  combatState.turn++;
  rollAllEnemyIntents();
  processPlayerStartOfTurn();

  return { success: true, phase: 'player_action' };
}

/**
 * Execute all enemy actions
 */
function executeEnemyActions() {
  combatState.enemies.forEach(enemy => {
    if (enemy.health <= 0) return;

    // Spawned this turn — skip action (shows Unknown intent on spawn turn)
    if (enemy.justSpawned) return;

    // Check Stun — skip turn and consume one stack
    if (enemy.statuses['stun'] && enemy.statuses['stun'] > 0) {
      enemy.statuses['stun']--;
      if (enemy.statuses['stun'] <= 0) delete enemy.statuses['stun'];
      addLog(`${enemy.name} is stunned and skips their turn!`, 'warning');
      return;
    }

    // Reset enemy block
    if (!enemy.statuses['barricade']) {
      enemy.block = 0;
    } else {
      enemy.block = Math.floor(enemy.block / 2);
    }

    // Execute intents
    if (enemy.currentIntent) {
      enemy.currentIntent.forEach(intent => {
        if (intent.resolved) return;

        const face = intent.face;
        if (face.isBlank) {
          addLog(`${enemy.name} does nothing`, 'info');
          return;
        }

        // Apply Power bonus to enemy damage
        const powerBonus = enemy.statuses['power'] || 0;

        face.effects.forEach(effect => {
          // Resolve value - rolls dice if D6/D8/etc. notation present
          const resolved = resolveEffectValue(effect);
          let value = resolved.value;
          if (resolved.isDiceAttack) {
            addLog(`${enemy.name} rolls dice: ${resolved.rollDetails} = ${value}`, 'info');
            // Allow player to spend a reroll ONLY if this enemy has the Rerollable status
            if (enemy.statuses['rerollable'] && combatState.player.rerolls > 0) {
              combatState.player.rerolls--;
              const rerolled = rollDiceNotation(effect.raw || '');
              addLog(`Reroll used! New roll: ${rerolled.rolls.map(r=>`d${r.die}:${r.result}`).join(', ')} = ${rerolled.total}`, 'success');
              value = rerolled.total;
            }
          }

          // Add power bonus to Dmg, arcane bonus to Magic Dmg
          if (effect.move?.toLowerCase() === 'dmg') {
            value += powerBonus;
          }
          if (effect.move?.toLowerCase() === 'magic dmg') {
            value += (enemy.statuses['arcane'] || 0);
          }

          // Process effect (targeting player)
          switch (effect.move?.toLowerCase()) {
            case 'dmg': {
              const addons = effect.addons || [];
              const hasOverload      = addons.some(a => a.toLowerCase() === 'overload');
              const hasExceptLeft    = addons.some(a => a.toLowerCase() === 'overloadexceptleft');
              const hasExceptRight   = addons.some(a => a.toLowerCase() === 'overloadexceptright');
              const isAoE = hasOverload || hasExceptLeft || hasExceptRight;

              // Helper: deal one hit to a target, resolving dice or fixed damage
              const dealHit = (target, dmgPerHit) => {
                if (target === combatState.player || (combatState.allies && combatState.allies.includes(target))) {
                  dealDamageToPlayer(dmgPerHit, addons, enemy);
                } else {
                  dealDamage(target, dmgPerHit, addons);
                }
              };

              if (effect.diceGroups && effect.diceGroups.length > 0) {
                // Dice attack: each group is a separate batch of hits
                const diceStr = effect.diceGroups.map(g => `${g.count}d${g.sides}`).join('+');
                addLog(`${enemy.name} rolls ${diceStr}!`, 'info');
                effect.diceGroups.forEach(group => {
                  for (let t = 0; t < group.count; t++) {
                    let roll = Math.floor(Math.random() * group.sides) + 1;
                    if (enemy.statuses['weak']) roll = Math.floor(roll * 0.75);
                    // Player hit (always)
                    dealDamageToPlayer(roll, addons, enemy);
                    // AoE: hit allies and other enemies
                    if (isAoE) {
                      (combatState.allies || []).forEach(a => { if (a.isAlive) dealDamage(a, roll, addons); });
                      combatState.enemies.forEach(oe => {
                        if (oe === enemy || oe.health <= 0) return;
                        if (hasExceptLeft  && oe.position < enemy.position) return;
                        if (hasExceptRight && oe.position > enemy.position) return;
                        dealDamage(oe, roll, addons);
                      });
                    }
                  }
                });
              } else {
                // Fixed damage (NxM or simple)
                let dmgVal = value;
                if (enemy.statuses['weak']) dmgVal = Math.floor(dmgVal * 0.75);
                const hitCount = effect.times || 1;
                for (let t = 0; t < hitCount; t++) {
                  dealDamageToPlayer(dmgVal, addons, enemy);
                  if (isAoE) {
                    (combatState.allies || []).forEach(a => { if (a.isAlive) dealDamage(a, dmgVal, addons); });
                    combatState.enemies.forEach(oe => {
                      if (oe === enemy || oe.health <= 0) return;
                      if (hasExceptLeft  && oe.position < enemy.position) return;
                      if (hasExceptRight && oe.position > enemy.position) return;
                      dealDamage(oe, dmgVal, addons);
                    });
                  }
                }
              }
              // Extract embedded status inflictions packed into Dmg addons
              // e.g. addons ["1","Burn"] → inflict 1 Burn on player
              {
                for (let ai = 0; ai + 1 < addons.length; ai++) {
                  if (/^\d+$/.test(addons[ai]) && PATTERN_STATUSES.has(addons[ai + 1].toLowerCase())) {
                    const sKey   = addons[ai + 1].toLowerCase();
                    const sCount = parseInt(addons[ai]);
                    combatState.player.statuses[sKey] = (combatState.player.statuses[sKey] || 0) + sCount;
                    addLog(`${enemy.name} inflicted ${sCount} ${addons[ai + 1]}`, 'warning');
                    ai++;
                  }
                }
              }
              break;
            }

            case 'magic dmg': {
              const magicAddons = ['magic', ...(effect.addons || [])];
              let magicDmgVal = value;
              if (enemy.statuses['weak']) magicDmgVal = Math.floor(magicDmgVal * 0.75);
              dealDamageToPlayer(magicDmgVal, magicAddons, enemy);
              if (effect.element) applyElement(combatState.player, effect.element);
              break;
            }

            case 'x': {
              // Turn-scaling damage: value × current turn number (legacy handler)
              let dmgVal = value * combatState.turn;
              if (enemy.statuses['weak']) dmgVal = Math.floor(dmgVal * 0.75);
              dealDamageToPlayer(dmgVal, [], enemy);
              addLog(`${enemy.name} deals ${dmgVal} (${value}×turn ${combatState.turn})`, 'info');
              break;
            }

            case 'block':
              addBlock(enemy, value);
              break;

            case 'heal':
              healTarget(enemy, value);
              break;

            case 'get': {
              const statusName = effect.target?.toLowerCase();
              if (statusName) {
                enemy.statuses[statusName] = (enemy.statuses[statusName] || 0) + value;
                addLog(`${enemy.name} gained ${value} ${effect.target}`, 'info');
              }
              break;
            }

            case 'inflict': {
              const inflictStatus = effect.target?.toLowerCase();
              if (inflictStatus) {
                const isAoE = (effect.addons || []).some(a =>
                  ['overload','wide'].includes(a.toLowerCase()));
                if (isAoE) {
                  // Inflict on player + all allies
                  applyStatus(combatState.player, inflictStatus, value);
                  combatState.allies.forEach(a => {
                    if (a.isAlive) applyStatus(a, inflictStatus, value);
                  });
                  addLog(`${enemy.name} inflicted ${value} ${effect.target} on all targets!`, 'warning');
                } else {
                  applyStatus(combatState.player, inflictStatus, value);
                  addLog(`${enemy.name} inflicted ${value} ${effect.target}`, 'warning');
                }
              }
              break;
            }

            case 'spawn':
              if (effect.target) {
                spawnEnemyAtSlot(effect.target, enemy.position + combatState.enemies.length);
              }
              break;

            case 'split': {
              if (enemy.splitAbility && !enemy.splitAbility.triggered) {
                enemy.splitAbility.triggered = true;
                const { count, spawnName } = enemy.splitAbility;
                const splitHp = Math.max(1, enemy.health);
                addLog(`${enemy.name} splits into ${count} ${spawnName}!`, 'warning');
                for (let s = 0; s < count; s++) {
                  spawnSplitEnemy(spawnName, splitHp);
                }
                // Remove the original enemy
                enemy.health = 0;
                onEnemyDefeated(enemy);
              }
              break;
            }

            case 'alter': {
              // Transform enemy into another form, keeping current HP
              const targetForm = effect.target;
              if (typeof ENEMIES_DATA !== 'undefined' && targetForm) {
                const tmpl = ENEMIES_DATA.find(e => e.name === targetForm);
                if (tmpl) {
                  const isOrd = /Turn \d+:/i.test(tmpl.pattern || '');
                  enemy.name            = tmpl.name;
                  enemy.ability         = tmpl.ability;
                  enemy.pattern         = tmpl.pattern || '';
                  enemy.patternType     = isOrd ? 'ordered' : 'random';
                  enemy.patternTurns    = isOrd ? parseOrderedPattern(tmpl.pattern) : null;
                  enemy.patternTurnIndex = 0;
                  enemy.dice            = tmpl.dice;
                  enemy.imageUrl        = tmpl.imageUrl;
                  enemy.staggerThreshold = parseStaggerThreshold(tmpl.ability);
                  enemy.rolledFaces     = new Set();
                  Object.assign(enemy.statuses, parseStartingAbilities(tmpl.ability));
                  addLog(`Transformed into ${tmpl.name}!`, 'warning');
                  rollEnemyIntent(enemy);
                  if (typeof window.updateCombatDisplay === 'function') window.updateCombatDisplay();
                } else {
                  addLog(`${enemy.name}: cannot find form "${targetForm}"`, 'warning');
                }
              }
              break;
            }

            case 'addpigment': {
              // "to deck" → discard pile (shuffled in later); otherwise → hand
              const toDeck = /\bto\s+(?:your\s+)?deck\b/i.test(effect.raw || '');
              if (toDeck) {
                if (typeof window.addRandomPigmentToDeck === 'function') {
                  window.addRandomPigmentToDeck();
                  addLog(`${enemy.name} added a Pigment card to your deck!`, 'warning');
                }
              } else {
                if (typeof window.addRandomPigmentToHand === 'function') {
                  window.addRandomPigmentToHand();
                  addLog(`${enemy.name} added a Pigment card to your hand!`, 'warning');
                }
              }
              break;
            }

            case 'addtodiscard': {
              // Add N copies of a named card to the player's discard pile
              const addCount = effect.value || 1;
              const addName  = effect.target || '';
              if (addName && typeof CARDS_DATA !== 'undefined') {
                const tmpl = CARDS_DATA.find(c => c.name.toLowerCase() === addName.toLowerCase());
                if (tmpl) {
                  for (let ci = 0; ci < addCount; ci++) {
                    combatState.discardPile.push({
                      ...tmpl,
                      id: `status_card_${Date.now()}_${ci}`,
                      isStatusCard: false  // playable; description handles exhaust
                    });
                  }
                  addLog(`${enemy.name} added ${addCount} ${addName} to your discard!`, 'warning');
                } else {
                  addLog(`${enemy.name}: could not find card "${addName}"`, 'info');
                }
              }
              break;
            }

            case 'consumepigment': {
              // Consume a random pigment from any pile; reward enemy with Power + Block
              const consumed = consumeRandomPigmentCard();
              if (consumed) {
                if (effect.power) {
                  enemy.statuses['power'] = (enemy.statuses['power'] || 0) + effect.power;
                  addLog(`${enemy.name} gained ${effect.power} Power from Pigment!`, 'warning');
                }
                if (effect.block) {
                  addBlock(enemy, effect.block);
                }
              } else {
                addLog(`${enemy.name} tried to consume Pigment but none found`, 'info');
              }
              break;
            }

            case 'pain': {
              // Pain = direct self-damage, bypasses block/thorns/dodge
              const painVal = value || (effect.addons && parseInt(effect.addons[0])) || 0;
              if (painVal > 0) {
                enemy.health -= painVal;
                addLog(`${enemy.name} took ${painVal} pain (self-damage)`, 'danger');
              }
              break;
            }

            case 'lose': {
              // "Lose All <Status>" removes all stacks; "Lose N <Status>" removes N stacks
              const loseKey = effect.target?.toLowerCase().replace(/\s+/g, '_');
              if (loseKey) {
                if (effect.all) {
                  delete enemy.statuses[loseKey];
                  addLog(`${enemy.name} lost all ${effect.target}`, 'info');
                } else {
                  const current = enemy.statuses[loseKey] || 0;
                  const remaining = Math.max(0, current - (effect.value || 0));
                  if (remaining <= 0) delete enemy.statuses[loseKey];
                  else enemy.statuses[loseKey] = remaining;
                  addLog(`${enemy.name} lost ${effect.value} ${effect.target}`, 'info');
                }
              }
              break;
            }

            default: {
              // If the move type is a known status name, treat it as inflict-on-player
              const unknownMove = effect.move?.toLowerCase();
              if (unknownMove && PATTERN_STATUSES.has(unknownMove)) {
                combatState.player.statuses[unknownMove] =
                  (combatState.player.statuses[unknownMove] || 0) + value;
                addLog(`${enemy.name} inflicted ${value} ${effect.move}`, 'warning');
              }
              break;
            }
          }
        });

        intent.resolved = true;
      });
    }

    // Apply Ritual at end of turn
    if (enemy.statuses['ritual']) {
      enemy.statuses['power'] = (enemy.statuses['power'] || 0) + enemy.statuses['ritual'];
      addLog(`${enemy.name}'s Ritual grants ${enemy.statuses['ritual']} Power`, 'warning');
    }
  });
}

/**
 * Deal damage to the player from an enemy
 * @param {number} damage - Damage amount
 * @param {Array} addons - Effect addons
 * @param {Object} enemy - Attacking enemy
 */
function dealDamageToPlayer(damage, addons, enemy) {
  const player = combatState.player;
  const _hasRanged = addons && addons.some(a => a.toLowerCase() === 'ranged');
  const isMeleeHit = !addons || (!_hasRanged && !addons.includes('self'));

  // Blind: enemy has 30% miss chance on attacks (not self-damage)
  if (enemy && (!addons || !addons.includes('self')) &&
      enemy.statuses && enemy.statuses['blind'] > 0) {
    if (Math.random() < 0.3) {
      combatState._lastMiss = 'enemy';
      addLog(`${enemy.name} missed! (Blind)`, 'info');
      return;
    }
  }

  // Offensive thorns: attacker's (enemy's) own thorns add to their melee attacks
  if (enemy && isMeleeHit) {
    const enemyThorns = (enemy.statuses && enemy.statuses['thorns']) || 0;
    if (enemyThorns > 0) damage += enemyThorns;
  }

  // Record hit for multi-hit visual playback
  if (combatState._hitLog !== undefined && isMeleeHit) {
    combatState._hitLog.push({ targetId: 'player', dmg: damage });
  }

  // Check Enfeebled (double damage taken)
  if (player.statuses['enfeebled']) {
    damage *= 2;
  }

  // Check Vulnerable (50% more incoming damage)
  if (player.statuses['vulnerable']) {
    damage = Math.ceil(damage * 1.5);
  }

  // Wet: fire immunity is handled via applyStatus interception (Burn blocked when Wet)

  // Check Bruise (melee/ranged attacks deal +1 per stack)
  const bruiseStacks = player.statuses['bruise'] || 0;
  const isDirectHit = !addons || !addons.includes('self');
  if (bruiseStacks > 0 && isDirectHit) {
    damage += bruiseStacks;
  }

  // Check Dodge
  if (player.statuses['dodge'] && player.statuses['dodge'] > 0) {
    player.statuses['dodge']--;
    if (player.statuses['dodge'] <= 0) {
      delete player.statuses['dodge'];
    }
    addLog('Dodged!', 'success');
    return;
  }

  // Check Brace (reduce incoming damage by 1 per stack, minimum 1 total)
  const braceStacks = player.statuses['brace'] || 0;
  if (braceStacks > 0) {
    damage = Math.max(1, damage - braceStacks);
  }

  // Player Thorns — fires on hit (regardless of block), not just on health loss.
  // Routes through dealDamage so enemy's block can absorb it. Only melee, not self/ranged.
  if (player.statuses['thorns'] && enemy && isMeleeHit) {
    dealDamage(enemy, player.statuses['thorns'], ['self']);
    addLog(`Thorns: ${player.statuses['thorns']} damage reflected to ${enemy.name}!`, 'info');
  }

  // Player Bleed Thorns — enemy melee hit applies Bleed to the attacker
  if (player.statuses['bleed_thorns'] && enemy && isMeleeHit) {
    const bleedStacks = player.statuses['bleed_thorns'];
    enemy.statuses['bleed'] = (enemy.statuses['bleed'] || 0) + bleedStacks;
    addLog(`Bleed Thorns: ${enemy.name} gained ${bleedStacks} Bleed!`, 'warning');
  }

  // Flame Barrier — fires on any hit (not self-damage), deals Magic Dmg Fire to attacker
  if (player.statuses['flame_barrier'] && enemy && !addons.includes('self')) {
    const fbDmg = player.statuses['flame_barrier'];
    dealDamage(enemy, fbDmg, ['magic', 'ranged']);
    applyFireElement(enemy);
    addLog(`Flame Barrier: ${fbDmg} Magic Dmg Fire reflected to ${enemy.name}!`, 'info');
  }

  // Apply block
  let remaining = damage;
  if (player.block > 0) {
    const blocked = Math.min(player.block, remaining);
    player.block -= blocked;
    remaining -= blocked;
    if (blocked > 0) {
      addLog(`Blocked ${blocked} damage`, 'info');
    }
  }

  // Deal damage
  if (remaining > 0) {
    // Buffer (Slay the Spire style): only triggers when player would lose health, not on blocked hits
    if (player.statuses['buffer'] && player.statuses['buffer'] > 0 && isDirectHit) {
      player.statuses['buffer']--;
      if (player.statuses['buffer'] <= 0) delete player.statuses['buffer'];
      addLog('Buffer absorbed the health loss!', 'success');
      return;
    }

    player.health -= remaining;
    window.health = player.health;
    combatState._playerHealthLossTimes = (combatState._playerHealthLossTimes || 0) + 1;
    addLog(`${enemy ? enemy.name : 'Unknown'} dealt ${remaining} damage!`, 'danger');

    // Plated Armor: lose 1 stack when taking unblocked damage
    if (player.statuses && player.statuses['plated_armor']) {
      player.statuses['plated_armor']--;
      if (player.statuses['plated_armor'] <= 0) delete player.statuses['plated_armor'];
    }

    // Soul Link — propagate health loss to all soul-linked enemies
    if (player.statuses['soul_link'] && !combatState._soulLinkPropagating) {
      combatState._soulLinkPropagating = true;
      combatState.enemies.forEach(e => {
        if (e.health > 0 && e.statuses['soul_link']) {
          dealDamage(e, remaining, ['self']);
        }
      });
      combatState._soulLinkPropagating = false;
    }

    // Prayer Card — 33% chance to gain +1 Buffer when taking damage
    const inv = typeof window.inventory !== 'undefined' ? window.inventory : [];
    if (inv.some(i => i.name === 'Prayer Card') && isDirectHit) {
      if (Math.random() < 0.33) {
        player.statuses['buffer'] = (player.statuses['buffer'] || 0) + 1;
        addLog('Prayer Card: +1 Buffer!', 'success');
      }
    }

    // Prayer Beads — +3 temporary Brace until end of next turn when taking damage
    if (inv.some(i => i.name === 'Prayer Beads') && isDirectHit) {
      player.statuses['brace'] = (player.statuses['brace'] || 0) + 3;
      player.statuses['brace_temp'] = (player.statuses['brace_temp'] || 0) + 3;
      addLog('Prayer Beads: +3 temporary Brace!', 'success');
    }


    // Rust — downgrade a random passive item when this enemy deals HP damage
    if (enemy && enemy.statuses['rust']) {
      if (typeof window.downgradeRandomPassiveItem === 'function') {
        window.downgradeRandomPassiveItem();
      }
    }

  }
}

/**
 * Apply a curse to the player based on the attacking enemy
 * @param {Object} enemy - The attacking enemy
 */
function applyCurseFromEnemy(enemy) {
  if (!enemy) return;

  // Map enemy type to curse stat (enemy type is already the stat name)
  const curseStat = enemy.type || 'Strength';

  // Map enemy difficulty to curse power
  const difficultyToPower = {
    'Low': 'Low',
    'Medium': 'Medium',
    'High': 'High'
  };
  const cursePower = difficultyToPower[enemy.difficulty] || 'Low';

  // Find matching curses from CURSES_DATA
  if (typeof CURSES_DATA !== 'undefined') {
    const matchingCurses = CURSES_DATA.filter(curse =>
      curse.stat === curseStat && curse.power === cursePower
    );

    if (matchingCurses.length > 0) {
      // Pick a random curse from matching ones
      const randomCurse = matchingCurses[Math.floor(Math.random() * matchingCurses.length)];

      // Apply the curse using StateMutator if available
      if (typeof StateMutator !== 'undefined' && StateMutator.addCurse) {
        StateMutator.addCurse(randomCurse.name, { updateUI: true, notify: true });
        addLog(`Cursed with ${randomCurse.name}!`, 'warning');
      } else if (typeof addCurse === 'function') {
        addCurse(randomCurse.name);
        addLog(`Cursed with ${randomCurse.name}!`, 'warning');
      } else {
        // Fallback: manually add curse
        if (!gameState.activeCurses) gameState.activeCurses = [];
        const curseInstance = {
          ...randomCurse,
          _id: `${randomCurse.name}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
        };
        gameState.activeCurses.push(curseInstance);
        addLog(`Cursed with ${randomCurse.name}!`, 'warning');
        if (typeof updateCursesDisplay === 'function') updateCursesDisplay();
        if (typeof updateTopBar === 'function') updateTopBar();
      }
    } else {
      console.warn(`No curse found for stat ${curseStat} with power ${cursePower}`);
    }
  }
}

/**
 * Process status effects on a target
 * @param {Object} target - Target entity
 * @param {string} timing - 'start' or 'end' of turn
 */
function processStatusEffects(target, timing) {
  const statuses = target.statuses;

  if (timing === 'start') {
    // Burn deals a flat 3 damage (not scaled by stacks); goes through block
    if (statuses['burn'] && !statuses['immune_burn']) {
      const total = statuses['oiled'] ? 6 : 3;
      addLog(`Burn dealt ${total} damage to ${target.name || 'Player'}`, 'danger');
      if (target === combatState.player) {
        dealDamageToPlayer(total, ['self'], null);
      } else {
        dealDamage(target, total, ['self']);
      }
    }

    // Poison deals damage at start
    if (statuses['poison']) {
      const poisonDamage = statuses['poison'];
      target.health -= poisonDamage;
      addLog(`Poison dealt ${poisonDamage} damage to ${target.name || 'Player'}`, 'danger');
      if (target === combatState.player) {
        window.health = target.health;
      }
    }
  }

  if (timing === 'end') {
    // Bleed: deal X damage (= stack count) at end of turn, then ESCALATE by 1
    if (statuses['bleed'] && statuses['bleed'] > 0) {
      const bleedDmg = statuses['bleed'];
      addLog(`Bleed dealt ${bleedDmg} damage to ${target.name || 'Player'}`, 'danger');
      if (target === combatState.player) {
        dealDamageToPlayer(bleedDmg, ['self'], null);
      } else {
        dealDamage(target, bleedDmg, ['self']);
      }
      statuses['bleed']++;
      addLog(`Bleed escalated to ${statuses['bleed']} on ${target.name || 'Player'}`, 'warning');
    }

    // Oiled: lose 1 energy at end of turn
    if (statuses['oiled'] && target === combatState.player) {
      const current = combatState.player.energy || 0;
      combatState.player.energy = Math.max(0, current - 1);
      addLog('Oiled: lost 1 energy', 'warning');
    }

    // Regeneration: heal X health at end of turn
    if (statuses['regeneration'] && statuses['regeneration'] > 0) {
      const regenAmount = statuses['regeneration'];
      target.health = Math.min(target.maxHealth, target.health + regenAmount);
      if (target === combatState.player) window.health = target.health;
      addLog(`${target.name || 'Player'} regenerated ${regenAmount} health`, 'success');
    }

    // Decay statuses
    const decayStatuses = ['burn', 'poison', 'oiled', 'frail', 'enfeebled', 'confused', 'barricade', 'vulnerable', 'weak', 'regeneration', 'double_damage', 'intangible', 'no_draw', 'blind', 'wet'];
    decayStatuses.forEach(status => {
      if (statuses[status]) {
        statuses[status]--;
        if (statuses[status] <= 0) {
          delete statuses[status];
        }
      }
    });

    // Metallicize: gain block at end of player's turn per stack
    if (target === combatState.player && statuses['metallicize']) {
      addBlock(combatState.player, statuses['metallicize']);
      addLog(`Metallicize: +${statuses['metallicize']} Block`, 'success');
    }

    // Plated Armor: gain X block at end of target's turn
    if (statuses['plated_armor']) {
      addBlock(target, statuses['plated_armor']);
      addLog(`Plated Armor: +${statuses['plated_armor']} Block`, 'success');
    }

    // Flame Barrier: remove all stacks at end of player's turn
    if (target === combatState.player && statuses['flame_barrier']) {
      delete statuses['flame_barrier'];
    }

    // Rage: clear per-turn attack block bonus
    if (target === combatState.player && combatState._rageBlock) {
      delete combatState._rageBlock;
    }

    // Double Tap: clear unused stacks at end of turn
    if (target === combatState.player && combatState._doubleTap) {
      delete combatState._doubleTap;
    }

    // Fiend Fire: clear hand exhaust count at end of turn
    if (target === combatState.player && combatState._exhaustedHandCount) {
      delete combatState._exhaustedHandCount;
    }

    // Combust: at end of player's turn, lose N HP and deal N×dmg Magic Dmg Fire to all enemies
    if (target === combatState.player && statuses['combust']) {
      const stacks = statuses['combust'];
      const dmgPerStack = combatState._combustDmgPerStack || 5;
      const combustTotal = stacks * dmgPerStack;
      loseHealth(stacks);
      combatState.enemies.filter(e => e.health > 0).forEach(e => {
        dealDamage(e, combustTotal, ['magic', 'ranged']);
        applyFireElement(e);
      });
      addLog(`Combust: lost ${stacks} HP, dealt ${combustTotal} Magic Dmg Fire to all enemies`, 'warning');
    }

    // Burst: clears completely at end of turn
    if (target === combatState.player && statuses['burst']) {
      delete statuses['burst'];
    }

    // Flex: remove temporary Power at end of player's turn
    if (target === combatState.player && combatState._flexPower) {
      const fp = combatState._flexPower;
      statuses['power'] = Math.max(0, (statuses['power'] || 0) - fp);
      if ((statuses['power'] || 0) <= 0) delete statuses['power'];
      delete combatState._flexPower;
    }

    // Fading
    if (statuses['fading']) {
      statuses['fading']--;
      if (statuses['fading'] <= 0) {
        target.health = 0;
        addLog(`${target.name} faded away!`, 'info');
        if (target !== combatState.player) onEnemyDefeated(target);
      }
    }

    // Shackled: target regains X Power at end of their turn, then Shackled clears
    if (statuses['shackled']) {
      const regain = statuses['shackled'];
      statuses['power'] = (statuses['power'] || 0) + regain;
      delete statuses['shackled'];
      addLog(`${target.name || 'Target'} regained ${regain} Power (Shackled expired)`, 'info');
    }
  }
}

// ============== UTILITY ==============

/**
 * Add message to combat log
 * @param {string} message - Log message
 * @param {string} type - 'info', 'success', 'warning', 'danger'
 */
function addLog(message, type = 'info') {
  if (!combatState) return;

  combatState.log.push({
    message: message,
    type: type,
    timestamp: Date.now()
  });
}

/**
 * Get current combat state
 * @returns {Object} Combat state or null
 */
function getCombatState() {
  return combatState;
}

/**
 * End combat
 * @param {boolean} victory - Whether player won
 * @returns {Object} Combat result
 */
function endCombat(victory) {
  if (!combatState) return null;

  // Trigger onCombatEnd effects for all items (before clearing combat state)
  if (victory && typeof window.triggerOnCombatEnd === 'function') {
    window.triggerOnCombatEnd(combatState);
  }

  // Permanently destroy Training cards played this combat
  if (combatState._destroyCards && combatState._destroyCards.length > 0 &&
      typeof gameState !== 'undefined' && Array.isArray(gameState.deck)) {
    for (const cardName of combatState._destroyCards) {
      const idx = gameState.deck.findIndex(c => c.name === cardName);
      if (idx !== -1) {
        gameState.deck.splice(idx, 1);
      }
    }
  }

  // Restore free-cost overrides from Mummified Hand (cleanup)
  // (Cards are already removed from hand; no action needed here)

  const result = {
    victory: victory,
    turns: combatState.turn,
    log: combatState.log
  };

  combatState = null;

  return result;
}

// ============== CARD COMBAT SYSTEM ==============

const HAND_SIZE_LIMIT = 10;
const BASE_DRAW_PER_TURN = 5;

/**
 * Resolve a card name from the starting deck, handling plurals.
 * "Attacks" → matches card named "Attack", etc.
 */
function resolveStartingCardName(name) {
  if (!window.cards && !window.CARDS_DATA) return null;
  const pool = window.cards || window.CARDS_DATA || [];
  const exact = pool.find(c => c.name === name);
  if (exact) return exact;
  if (name.endsWith('s')) return pool.find(c => c.name === name.slice(0, -1)) || null;
  return null;
}

/**
 * Build the full combat deck from character starting deck + collected cards.
 */
function buildCombatDeck(characterData) {
  const deck = [];
  let uid = Date.now();

  // Starting deck from character data
  const startingDeck = characterData.startingDeck || [];
  const upgradedStarting = (typeof gameState !== 'undefined' && gameState.upgradedStartingCards) || {};
  const removedStarting  = (typeof gameState !== 'undefined' && gameState.removedStartingCards)  || {};
  for (const entry of startingDeck) {
    const template = resolveStartingCardName(entry.cardName);
    if (template) {
      const totalRaw = entry.count || 1;
      const removed = removedStarting[entry.cardName] || 0;
      const total = Math.max(0, totalRaw - removed);
      const val = upgradedStarting[entry.cardName];
      // Support both legacy boolean (upgrade all) and new count-based tracking
      const upgradedCount = typeof val === 'number' ? Math.min(val, total) : (val ? total : 0);
      for (let i = 0; i < total; i++) {
        const wasSmithUpgraded = i < upgradedCount;
        const card = { ...template, upgraded: wasSmithUpgraded, _uid: `start_${uid++}` };
        if (wasSmithUpgraded) {
          if (card.upgradedDescription) card.description = card.upgradedDescription;
          if (card.upgradedCost !== null && card.upgradedCost !== undefined) card.cost = card.upgradedCost;
        }
        deck.push(card);
      }
    } else {
      console.warn('Starting deck card not found:', entry.cardName);
    }
  }

  // Collected cards from gameState.deck
  const collected = (typeof gameState !== 'undefined' && gameState.deck) ? gameState.deck : [];
  for (const card of collected) {
    deck.push({ ...card, _uid: `run_${uid++}` });
  }

  return deck;
}

function shuffleArray(arr) {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/**
 * Initialize the card deck system at combat start.
 */
function initCombatDeck(characterData) {
  const fullDeck = buildCombatDeck(characterData);
  const shuffled = shuffleArray(fullDeck);
  // Innate: move Innate cards to the top of the draw pile
  const innate = shuffled.filter(c => (c.description || '').toLowerCase().includes('innate'));
  const rest   = shuffled.filter(c => !(c.description || '').toLowerCase().includes('innate'));
  combatState.drawPile = [...innate, ...rest];
  combatState.hand = [];
  combatState.discardPile = [];
  combatState.exhaustPile = [];
  combatState.powers = [];
  combatState.selectedCardIndex = null;
  combatState.reshuffleQueued = false;
  addLog(`Deck initialized: ${fullDeck.length} cards`, 'info');
}

/**
 * Draw cards from draw pile into hand. Reshuffles discard if needed.
 * @returns {Array} Cards drawn
 */
function drawCards(count = 1) {
  const drawn = [];
  // No Draw: player cannot draw cards this turn
  if (combatState.player.statuses['no_draw']) return drawn;
  for (let i = 0; i < count; i++) {
    if (combatState.hand.length >= HAND_SIZE_LIMIT) break;

    if (combatState.drawPile.length === 0) {
      if (combatState.discardPile.length === 0) break;
      combatState.drawPile = shuffleArray([...combatState.discardPile]);
      combatState.discardPile = [];
      combatState.reshuffleQueued = true;
      addLog('Reshuffled discard pile into draw pile', 'info');
    }

    const card = combatState.drawPile.shift();
    combatState.hand.push(card);
    drawn.push(card);
    combatState._lastDrawnCard = card;

    // Evolve: whenever a status card is drawn, draw X more cards
    if (card.isStatusCard && !combatState._evolveFiring &&
        combatState.player.statuses && combatState.player.statuses['evolve']) {
      combatState._evolveFiring = true;
      const evolveDraw = combatState.player.statuses['evolve'];
      addLog(`Evolve: drew ${card.name} (status), drawing ${evolveDraw} more`, 'success');
      drawCards(evolveDraw);
      combatState._evolveFiring = false;
    }

    // Fire Breathing: whenever a status or curse card is drawn, deal Magic Dmg Fire AoE ranged
    if ((card.isStatusCard || card.isCurse || (card.type || '').toLowerCase() === 'curse') && !combatState._fireBreathFiring &&
        combatState.player.statuses && combatState.player.statuses['fire_breathing']) {
      combatState._fireBreathFiring = true;
      const fb = combatState.player.statuses['fire_breathing'];
      combatState.enemies.filter(e => e.health > 0).forEach(e => {
        dealDamage(e, fb, ['magic', 'ranged']);
        applyFireElement(e);
      });
      addLog(`Fire Breathing: ${fb} Magic Dmg Fire to all enemies`, 'warning');
      combatState._fireBreathFiring = false;
    }

    // Endless Agony: whenever drawn, add a copy to the draw pile
    if (/Whenever you draw this card,.*(?:add a copy to your Draw Pile|Conjure.*copy.*to Draw)/i.test(card.description || '')) {
      combatState.drawPile.push({ ...card, _uid: `ea_copy_${Date.now()}` });
      addLog(`${card.name}: added a copy to the draw pile`, 'info');
    }
  }
  return drawn;
}

/**
 * Determine if a card requires clicking an enemy target.
 */
function cardNeedsTarget(card) {
  const desc = (card.description || '').toLowerCase();
  const type = (card.type || '').toLowerCase();
  if (type === 'power' || type === 'status') return false;
  if (type === 'dice') return false;
  if (desc.includes('cleave') || desc.includes('all enemies') || desc.includes('indiscriminate')) return false;
  if (type === 'attack') return true;
  // Skill cards that inflict/apply statuses on a single enemy need a target selection
  // (excludes AoE keywords above; excludes "random target" which picks automatically)
  if (type === 'skill' && /(?:inflict|apply)\s+/i.test(card.description || '') && !desc.includes('random target')) return true;
  return false;
}

/**
 * Resolve a card's effects when played.
 * @returns {boolean} True if card should be exhausted rather than discarded
 */
// Parse "N: effect text" dice face lines from a card description
function parseDiceFacesForEngine(description) {
  if (!description) return [];
  return description
    .split(/[\r\n]+/)
    .map(line => line.match(/^(\d+):\s*(.+)$/))
    .filter(Boolean)
    .map(m => ({ num: parseInt(m[1]), text: m[2].trim() }));
}

function resolveCardEffect(card, target, options = {}) {
  const desc = card.description || '';
  let shouldExhaust = false;
  const player = combatState.player;
  const xValue = options.xValue || 0;

  // Status cards always exhaust (they are one-use pigments that clear after combat)
  if (card.isStatusCard) shouldExhaust = true;

  // Dice cards: the UI handles pick + roll + transform; nothing to resolve here.
  if ((card.type || '').toLowerCase() === 'dice') {
    return shouldExhaust;
  }

  // Machine Learning: grants +1 draw at the start of each turn (separate stacking)
  if (card.name === 'Machine Learning') {
    if (!Array.isArray(player.statuses['machine_learning'])) {
      player.statuses['machine_learning'] = Array.isArray(player.statuses['machine_learning'])
        ? player.statuses['machine_learning'] : [];
    }
    player.statuses['machine_learning'].push(1);
    addLog('Machine Learning: +1 draw per turn!', 'success');
    return shouldExhaust;
  }

  // Pre-scan the whole description for AoE keywords (they may be in a separate clause)
  const fullDescLower = desc.toLowerCase();
  // Cleave hits all enemies AND all allies (sweeping AoE)
  // Indiscriminate / "all enemies" hit only all enemies
  const isCleaveCard = fullDescLower.includes('cleave');
  const isAoECard    = isCleaveCard || fullDescLower.includes('all enemies')
                    || fullDescLower.includes('indiscriminate');
  // Lifesteal: flag so dealDamage can heal player equal to unblocked damage dealt
  const isLifestealCard = fullDescLower.includes('lifesteal');
  if (isLifestealCard) combatState._lifestealActive = true;

  // Heavy Blade: pre-scan for power multiplier (e.g. "Power affects this card x3 times")
  let _powerMultiplier = 1;
  const _heavyBladeM = desc.match(/Power affects this card x(\d+) times?/i);
  if (_heavyBladeM) _powerMultiplier = parseInt(_heavyBladeM[1]);

  // Wealth: +1 damage per 10 gold the player has
  const _wealthBonus = fullDescLower.includes('wealth')
    ? Math.floor((typeof gold !== 'undefined' ? gold : (gameState?.gold || 0)) / 10)
    : 0;

  // Split effects by '. ' to handle multi-effect cards
  const parts = desc.replace(/\.\s*$/, '').split(/\.\s+/);

  // Combust Power: register stacks before part parsing (effect fires each end-of-turn, not immediately)
  if (card.name === 'Combust') {
    player.statuses['combust'] = (player.statuses['combust'] || 0) + 1;
    const dmgM = desc.match(/Deal (\d+) Magic Dmg/i);
    if (dmgM) combatState._combustDmgPerStack = parseInt(dmgM[1]);
    addLog(`Combust: ${player.statuses['combust']} stack(s) active`, 'info');
  }

  // Metallicize Power: register stacks before part parsing (end-of-turn block)
  if (card.name === 'Metallicize') {
    const mM = desc.match(/Gain \+?(\d+) Block/i);
    player.statuses['metallicize'] = (player.statuses['metallicize'] || 0) + (mM ? parseInt(mM[1]) : 3);
    addLog(`Metallicize: +${mM ? parseInt(mM[1]) : 3} Block each turn`, 'info');
  }

  for (const part of parts) {
    const p = part.trim();
    if (!p) continue;
    const lower = p.toLowerCase();

    if (lower === 'exhaust') { shouldExhaust = true; continue; }
    if (lower === 'ethereal') { continue; } // Ethereal exhausts at end of turn if still in hand, not on play
    if (lower === 'indiscriminate' || lower === 'cleave') { continue; } // handled above via isAoECard
    if (lower === 'sly' || lower === 'innate' || lower === 'unplayable') { continue; }

    // Skip "at the end of your turn" clauses — recurring effects handled by processStatusEffects
    if (/at the end of your turn/i.test(lower)) continue;

    // Skip "Whenever you draw this card" clauses — draw-triggered effects handled in drawCards()
    if (/whenever you draw this card/i.test(lower)) continue;

    // Gain +N Flame Barrier (status that retaliates with Magic Dmg Fire, expires end of turn)
    const flameBarrierM = p.match(/Gain \+?(\d+) Flame Barrier/i);
    if (flameBarrierM) {
      const amt = parseInt(flameBarrierM[1]);
      player.statuses['flame_barrier'] = (player.statuses['flame_barrier'] || 0) + amt;
      addLog(`+${amt} Flame Barrier`, 'success');
      continue;
    }

    // Gain +N Feel No Pain (register on-exhaust block)
    const feelNoPainM = p.match(/Gain \+?(\d+) Feel No Pain/i);
    if (feelNoPainM) {
      player.statuses['feel_no_pain'] = (player.statuses['feel_no_pain'] || 0) + parseInt(feelNoPainM[1]);
      addLog(`+${feelNoPainM[1]} Feel No Pain`, 'info');
      continue;
    }

    // Gain +N Fire Breathing (register on-draw-status damage)
    const fireBreathM = p.match(/Gain \+?(\d+) Fire Breathing/i);
    if (fireBreathM) {
      player.statuses['fire_breathing'] = (player.statuses['fire_breathing'] || 0) + parseInt(fireBreathM[1]);
      addLog(`+${fireBreathM[1]} Fire Breathing`, 'info');
      continue;
    }

    // Rupture Power: register "whenever you lose health from a card, gain +N power"
    const ruptureM = p.match(/Whenever you lose Health from a Card, Gain \+?(\d+) Power/i);
    if (ruptureM) {
      player.statuses['rupture_power'] = (player.statuses['rupture_power'] || 0) + parseInt(ruptureM[1]);
      addLog(`Rupture: will gain +${ruptureM[1]} Power per health loss from cards`, 'success');
      continue;
    }

    // Skip "Sequential Upgrade Dmg/Magic Dmg +N" — informational flavor text, not an executable effect
    if (/Sequential Upgrade (?:Magic )?Dmg \+\d+/i.test(p)) { continue; }

    // Until the end of your turn, whenever you play an Attack, Gain +N Block (Rage)
    const rageM = p.match(/Until the end of your turn.*whenever you play an Attack.*Gain \+?(\d+) Block/i);
    if (rageM) {
      combatState._rageBlock = (combatState._rageBlock || 0) + parseInt(rageM[1]);
      addLog(`Rage: +${combatState._rageBlock} Block per Attack this turn`, 'success');
      continue;
    }

    // Increase the Dmg of this Card by N this combat (Rampage self-scaling)
    const selfScaleM = p.match(/Increase the Dmg of this Card by \+?(\d+) this combat/i);
    if (selfScaleM) {
      const inc = parseInt(selfScaleM[1]);
      if (!combatState._scalingCounters) combatState._scalingCounters = {};
      combatState._scalingCounters[card.name] = (combatState._scalingCounters[card.name] || 0) + inc;
      addLog(`${card.name}: +${inc} Dmg this combat (total: +${combatState._scalingCounters[card.name]})`, 'success');
      continue;
    }

    // Gain Double Block (Entrench)
    if (/Gain Double Block/i.test(lower)) {
      player.block = (player.block || 0) * 2;
      addLog(`Entrench: Block doubled to ${player.block}`, 'success');
      continue;
    }

    // Gain +N Evolve (Evolve card)
    const evolveGainMatch = p.match(/Gain \+?(\d+) Evolve/i);
    if (evolveGainMatch) {
      player.statuses['evolve'] = (player.statuses['evolve'] || 0) + parseInt(evolveGainMatch[1]);
      addLog(`+${evolveGainMatch[1]} Evolve`, 'info');
      continue;
    }

    // Whenever a Card is Exhausted, Draw X Card(s) (Dark Embrace)
    if (/Whenever a Card is Exhausted/i.test(p)) {
      const drawM = p.match(/Draw (\d+) Card/i);
      const draws = drawM ? parseInt(drawM[1]) : 1;
      player.statuses['dark_embrace'] = (player.statuses['dark_embrace'] || 0) + draws;
      addLog(`Dark Embrace: ${player.statuses['dark_embrace']} stack(s)`, 'info');
      continue;
    }

    // If the target has Vulnerable, gain energy and draw (Dropkick)
    if (/If the target has Vulnerable/i.test(p)) {
      if (target && target.statuses && target.statuses['vulnerable']) {
        const eM = p.match(/Gain \+?(\d+) Energy/i);
        const dM = p.match(/Draw (\d+) Card/i);
        if (eM) { player.energy += parseInt(eM[1]); addLog('Dropkick: +1 Energy!', 'success'); }
        if (dM) drawCards(parseInt(dM[1]));
      }
      continue;
    }

    // Choose an Attack or Power Card (Dual Wield part 1 — handled by Conjure step below)
    if (/Choose an Attack or Power Card/i.test(p)) continue;

    // Conjure N Copy/Copies of that Card to Hand (Dual Wield) — before generic Conjure handler
    if (/Conjure \d+ Cop(?:y|ies) of that Card to Hand/i.test(p)) {
      const cM = p.match(/Conjure (\d+)/i);
      const copyCount = cM ? parseInt(cM[1]) : 1;
      const handFilterd = combatState.hand.filter(c => ['attack', 'power'].includes((c.type || '').toLowerCase()));
      if (handFilterd.length > 0) {
        combatState._pendingCardPick = {
          action: 'copy',
          pile: 'hand',
          count: 1,
          _copyCount: copyCount,
          _typesAllowed: ['attack', 'power']
        };
      }
      continue;
    }

    // Deal NxX Dmg — Skewer-style: N damage, X times where X = energy spent (xValue)
    const dmgMatchNxX = p.match(/Deal (\d+)[xX]X Dmg/i);
    if (dmgMatchNxX && xValue > 0) {
      let dmg   = parseInt(dmgMatchNxX[1]);
      const times = xValue;
      const playerPower = player.statuses['power'] || 0;
      if (playerPower !== 0) dmg += playerPower;
      // Shiv bonus from Accuracy
      if (card.name === 'Shiv' || (card.tags && card.tags.includes('shiv'))) {
        dmg += player.statuses['shiv_damage_bonus'] || 0;
      }
      if (player.statuses['weak']) dmg = Math.floor(dmg * 0.75);
      // Pass melee/ranged addon so dealDamage can apply flat bonuses (e.g. Focus Crystal)
      const nxxAddons = /melee/i.test(p) ? ['melee'] : /ranged/i.test(p) ? ['ranged'] : [];
      if (isAoECard) {
        combatState.enemies.filter(e => e.health > 0).forEach(e => {
          for (let t = 0; t < times; t++) dealDamage(e, dmg, nxxAddons);
        });
      } else if (target) {
        for (let t = 0; t < times; t++) dealDamage(target, dmg, nxxAddons);
      }
      addLog(`${card.name}: ${dmg} x${times} = ${dmg * times} damage`, 'info');
      continue;
    }

    // Deal N Magic Dmg [Element] — scales with Arcane (not Power), may trigger element effects
    const magicDmgMatchNxM = p.match(/Deal (\d+)[xX](\d+) Magic Dmg(?:\s+(Fire|Ice|Lightning))?/i);
    const magicDmgMatch    = magicDmgMatchNxM || p.match(/Deal (\d+) Magic Dmg(?:\s+(Fire|Ice|Lightning))?/i);
    if (magicDmgMatch) {
      let dmg = parseInt(magicDmgMatch[1]);
      const times   = magicDmgMatchNxM ? parseInt(magicDmgMatchNxM[2]) : 1;
      const element = (magicDmgMatchNxM ? magicDmgMatchNxM[3] : magicDmgMatch[2] || null);
      const elementLow = element ? element.toLowerCase() : null;
      // Arcane bonus instead of Power
      const playerArcane = player.statuses['arcane'] || 0;
      if (playerArcane !== 0) dmg += playerArcane;
      // Weak reduces outgoing damage by 25%
      if (player.statuses['weak']) dmg = Math.floor(dmg * 0.75);
      const magicHitAddons = /melee/i.test(p) ? ['magic', 'melee'] : /ranged/i.test(p) ? ['magic', 'ranged'] : ['magic'];
      const magicTargets = isAoECard
        ? combatState.enemies.filter(e => e.health > 0)
        : (target ? [target] : []);
      magicTargets.forEach(e => {
        for (let t = 0; t < times; t++) dealDamage(e, dmg, magicHitAddons);
        if (elementLow === 'fire') applyFireElement(e);
      });
      if (magicTargets.length > 0) addLog(`${card.name}: ${dmg} Magic Dmg${element ? ' ' + element : ''}`, 'info');
      continue;
    }

    // Deal X Dmg [Y times] — supports both "Deal 5 Dmg 2 times" and "Deal 5x2 Dmg" (NxM notation)
    const dmgMatchNxM = p.match(/Deal (\d+)[xX](\d+) Dmg/i);
    const dmgMatch    = dmgMatchNxM || p.match(/Deal (\d+) Dmg(?:.*?(\d+) times?)?/i);
    if (dmgMatch) {
      let dmg = parseInt(dmgMatch[1]);
      const times = dmgMatchNxM ? parseInt(dmgMatchNxM[2]) : (dmgMatch[2] ? parseInt(dmgMatch[2]) : 1);
      // Player Power bonus adds to outgoing damage (Heavy Blade multiplies it)
      const playerPower = player.statuses['power'] || 0;
      if (playerPower !== 0) dmg += playerPower * _powerMultiplier;
      // Pigment strength: only boost damage when it crosses the next /3 threshold
      const baseStr = (player.stats && player.stats.strength) || 0;
      const tempStr = player.statuses['strength'] || 0;
      const strBonus = Math.floor((baseStr + tempStr) / 3) - Math.floor(baseStr / 3);
      if (strBonus > 0) dmg += strBonus;
      // Dead Eye: apply accumulated consecutive-hit bonus if attacking the same target
      if (target && target !== player) {
        const _deInv = typeof window.inventory !== 'undefined' ? window.inventory : [];
        if (_deInv.some(i => i.name === 'Dead Eye')) {
          const targetId = target.id || target.name;
          if (combatState._deadEyeTarget === targetId) {
            dmg += combatState._deadEyeBonus || 0;
          }
          // Targeting a new enemy: bonus will be reset in dealDamage when streak changes
        }
      }
      // Accuracy: Shiv cards deal bonus damage
      if (card.name === 'Shiv' && player.statuses['shiv_damage_bonus']) {
        dmg += player.statuses['shiv_damage_bonus'];
      }
      // Scaling cards: apply accumulated per-combat bonus (e.g. Claw +2 per play)
      if (combatState._scalingCounters && combatState._scalingCounters[card.name]) {
        dmg += combatState._scalingCounters[card.name];
      }
      // Wealth: +1 per 10 gold
      if (_wealthBonus > 0) dmg += _wealthBonus;
      // Weak on player reduces outgoing damage by 25%
      if (player.statuses['weak']) {
        dmg = Math.floor(dmg * 0.75);
      }
      // Pass melee/ranged addon so dealDamage can apply flat bonuses (e.g. Focus Crystal)
      const hitAddons = /melee/i.test(p) ? ['melee'] : /ranged/i.test(p) ? ['ranged'] : [];
      if (isAoECard) {
        combatState.enemies.filter(e => e.health > 0).forEach(e => {
          for (let t = 0; t < times; t++) dealDamage(e, dmg, hitAddons);
        });
        // Cleave also hits all allies (sweeping attack that doesn't discriminate)
        if (isCleaveCard && combatState.allies) {
          combatState.allies.filter(a => a.isAlive).forEach(a => {
            for (let t = 0; t < times; t++) dealDamage(a, dmg, hitAddons);
          });
          if (combatState.allies.some(a => a.isAlive)) addLog('Cleave hit all allies too!', 'warning');
        }
      } else if (target) {
        for (let t = 0; t < times; t++) dealDamage(target, dmg, hitAddons);
      }

      // Strike-only item triggers (card named exactly "Strike")
      if ((card.name || '').toLowerCase() === 'strike') {
        const inv = typeof window.inventory !== 'undefined' ? window.inventory : [];

        // Strike Dummy: +3 damage per copy
        const strikeDummyCount = inv.filter(i => i.name === 'Strike Dummy').reduce((n, i) => n + (i.quantity || 1), 0);
        if (strikeDummyCount > 0) {
          const bonus = 3 * strikeDummyCount;
          if (isAoECard) {
            combatState.enemies.filter(e => e.health > 0).forEach(e => dealDamage(e, bonus));
          } else if (target) {
            dealDamage(target, bonus);
          }
        }

        if (target) {
          // Bird Head: inflict Soul Link
          if (inv.some(i => i.name === 'Bird Head')) {
            target.statuses['soul_link'] = 1;
            addLog(`Bird Head: ${target.name} is Soul Linked!`, 'warning');
          }

          // Brass Knuckles: inflict Bruise
          if (inv.some(i => i.name === 'Brass Knuckles')) {
            target.statuses['bruise'] = (target.statuses['bruise'] || 0) + 1;
            addLog(`Brass Knuckles: ${target.name} gains 1 Bruise!`, 'warning');
          }

          // Jar of Leeches: inflict Leeches
          if (inv.some(i => i.name === 'Jar of Leeches')) {
            target.statuses['leeches'] = (target.statuses['leeches'] || 0) + 1;
            target.statuses['leeches_owner'] = 'player';
            addLog(`Jar of Leeches: ${target.name} gains 1 Leeches!`, 'warning');
          }
        }

        // Leeching Seed: heal player for 1
        if (inv.some(i => i.name === 'Leeching Seed')) {
          healTarget(combatState.player, 1);
          addLog(`Leeching Seed: healed you for 1!`, 'success');
        }
      }
      continue;
    }

    // Gain X Block (handles "Gain 5 Block" and "Gain +5 Block")
    const blockMatch = p.match(/Gain \+?(\d+) Block/i);
    if (blockMatch) {
      const blockAmt = parseInt(blockMatch[1]);
      addBlock(player, blockAmt);
      card._lastBlockGain = blockAmt; // used by Dodge and Roll "Next Turn Block equal to Block Gained"
      continue;
    }

    // Draw X card(s) — skip if an earlier Exhaust clause will handle the draw via drawAfter
    const drawMatch = p.match(/Draw (\d+) cards?/i);
    if (drawMatch) {
      const hasExhaustBefore = parts.slice(0, parts.indexOf(p)).some(pp => /Exhaust \d+ Cards?/i.test(pp) && !/random/i.test(pp) && !/in your hand/i.test(pp));
      if (!hasExhaustBefore) drawCards(parseInt(drawMatch[1]));
      continue;
    }

    // Multi-status AoE: "Apply/Inflict N Status1 Cleave and [Apply/Inflict] N Status2 Cleave"
    // (Shockwave, Crippling Cloud, Piercing Wail) — must be checked BEFORE generic applyMatch
    const multiStatusAoE2 = p.match(/(?:Apply|Inflict) (-?\d+) (\w+) Cleave and (?:(?:Apply|Inflict) )?(-?\d+) (\w+) Cleave/i);
    if (multiStatusAoE2) {
      const enemies2 = combatState.enemies.filter(e => e.health > 0);
      const [, n1raw, s1, n2raw, s2] = multiStatusAoE2;
      const n1 = parseInt(n1raw), n2 = parseInt(n2raw);
      enemies2.forEach(e => {
        if (n1 < 0) {
          e.statuses['power'] = (e.statuses['power'] || 0) + n1;
        } else {
          e.statuses[s1.toLowerCase()] = (e.statuses[s1.toLowerCase()] || 0) + n1;
        }
        if (n2 < 0) {
          e.statuses['power'] = (e.statuses['power'] || 0) + n2;
        } else {
          e.statuses[s2.toLowerCase()] = (e.statuses[s2.toLowerCase()] || 0) + n2;
        }
      });
      addLog(`${card.name}: ${n1} ${s1} + ${n2} ${s2} to all enemies`, 'warning');
      continue;
    }

    // Inflict N Corpse Explosion (must be before general applyMatch to avoid "Corpse" single-word capture)
    const ceInflictMatch = p.match(/Inflict (\d+) Corpse Explosion/i);
    if (ceInflictMatch) {
      const targets = isAoECard
        ? combatState.enemies.filter(e => e.health > 0)
        : (target ? [target] : []);
      const stacks = parseInt(ceInflictMatch[1]);
      targets.forEach(t => {
        t.statuses['corpse_explosion'] = (t.statuses['corpse_explosion'] || 0) + stacks;
      });
      addLog(`Inflicted ${stacks} Corpse Explosion`, 'warning');
      continue;
    }

    // Apply / Inflict X [Status] (on current target or all enemies if AoE)
    const applyMatch = p.match(/(?:Apply|Inflict) (\d+) (\w+)/i);
    if (applyMatch) {
      const BASIC_STATS = new Set(['power', 'defense', 'arcane', 'persistence']);
      const key = applyMatch[2].toLowerCase();
      let stacks = parseInt(applyMatch[1]);
      // Persistence adds to non-basic buff/debuff status applications
      if (!BASIC_STATS.has(key)) {
        const statusDef = typeof STATUSES_DATA !== 'undefined' ? STATUSES_DATA[key] : null;
        if (statusDef && (statusDef.type === 'Buff' || statusDef.type === 'Debuff')) {
          stacks += (player.statuses['persistence'] || 0);
        }
      }
      const statusTargets = isAoECard
        ? combatState.enemies.filter(e => e.health > 0)
        : (target ? [target] : []);
      statusTargets.forEach(t => {
        t.statuses[key] = (t.statuses[key] || 0) + stacks;
        addLog(`Applied ${stacks} ${applyMatch[2]} to ${t.name}`, 'warning');
      });
      continue;
    }

    // Gain X Energy (handles "Gain 1 Energy" and "Gain +1 Energy")
    const energyMatch = p.match(/Gain \+?(\d+) Energy/i);
    if (energyMatch) {
      const e = parseInt(energyMatch[1]);
      player.energy += e;
      addLog(`Gained ${e} Energy`, 'success');
      continue;
    }

    // Lose X Health (direct health loss, not attack damage — triggers loseHealth)
    const loseHpMatch = p.match(/Lose (\d+) Health/i);
    if (loseHpMatch) {
      loseHealth(parseInt(loseHpMatch[1]));
      continue;
    }

    // X Infuse / Infuse X
    const infuseMatch = p.match(/(?:(\d+)\s+Infuse|Infuse\s+(\d+))/i);
    if (infuseMatch) {
      const amt = parseInt(infuseMatch[1] || infuseMatch[2]) || 1;
      // Grow maxMana if the player hasn't had their mana pool initialized yet
      if (player.maxMana === 0) player.maxMana = amt;
      player.mana = Math.min(player.maxMana, (player.mana || 0) + amt);
      addLog(`Infused ${amt} Mana`, 'info');
      continue;
    }

    // Barricade
    if (lower === 'gain barricade' || lower === 'barricade') {
      player.statuses['barricade'] = 1;
      addLog('Barricade: Block no longer expires', 'success');
      continue;
    }

    // Go for the Eyes: "If target intends to attack, Inflict N Status"
    const goForEyesMatch = p.match(/If target intends to attack, Inflict (\d+) (\w+)/i);
    if (goForEyesMatch) {
      const stacks = parseInt(goForEyesMatch[1]);
      const statusKey = goForEyesMatch[2].toLowerCase();
      if (target) {
        const isAttacking = target.currentIntent && target.currentIntent.some(
          intent => intent.face && intent.face.effects && intent.face.effects.some(e => e.move === 'Dmg')
        );
        if (isAttacking) {
          target.statuses[statusKey] = (target.statuses[statusKey] || 0) + stacks;
          addLog(`Go for the Eyes: ${stacks} ${goForEyesMatch[2]} (enemy intends to attack)!`, 'success');
        } else {
          addLog(`Go for the Eyes: enemy not attacking this turn`, 'info');
        }
      }
      continue;
    }

    // Spot Weakness: "If the target enemy intends to attack, Gain +N Power"
    const spotWeaknessM = p.match(/If the target enemy intends to attack, Gain \+?(\d+) Power/i);
    if (spotWeaknessM) {
      if (target) {
        const isAttacking = target.currentIntent && target.currentIntent.some(
          intent => intent.face && intent.face.effects && intent.face.effects.some(e => e.move === 'Dmg')
        );
        if (isAttacking) {
          const gain = parseInt(spotWeaknessM[1]);
          player.statuses['power'] = (player.statuses['power'] || 0) + gain;
          addLog(`Spot Weakness: +${gain} Power (enemy intends to attack)!`, 'success');
        } else {
          addLog(`Spot Weakness: enemy not attacking this turn`, 'info');
        }
      }
      continue;
    }

    // Berserk / similar: "At the start of your turn, Gain +N Energy" — register energy_per_turn
    const energyPerTurnM = p.match(/At the start of your turn, Gain \+?(\d+) Energy/i);
    if (energyPerTurnM) {
      const gain = parseInt(energyPerTurnM[1]);
      player.statuses['energy_per_turn'] = (player.statuses['energy_per_turn'] || 0) + gain;
      addLog(`Berserk: +${gain} Energy per turn`, 'success');
      continue;
    }

    // Brutality: "At the start of your turn, Lose N Health and Draw N Card"
    const brutalityM = p.match(/At the start of your turn, Lose (\d+) Health and Draw (\d+) Card/i);
    if (brutalityM) {
      player.statuses['brutality'] = 1;
      addLog('Brutality: will lose 1 HP and draw 1 card each turn', 'success');
      continue;
    }

    // Corruption: "Skills cost 0 Energy. Whenever you play a Skill, Exhaust it."
    if (/Skills cost 0 Energy/i.test(p) || /Whenever you play a Skill, Exhaust it/i.test(p)) {
      player.statuses['corruption'] = 1;
      addLog('Corruption: Skills cost 0 and exhaust on play', 'success');
      continue;
    }

    // Double Tap: "This turn, your next [N] Attack[s] is/are played twice"
    const doubleTapM = p.match(/This turn, your next (\d+ )?Attacks? (?:is|are) played twice/i);
    if (doubleTapM) {
      const taps = doubleTapM[1] ? parseInt(doubleTapM[1]) : 1;
      combatState._doubleTap = (combatState._doubleTap || 0) + taps;
      addLog(`Double Tap: next ${taps} Attack(s) will be played twice`, 'success');
      continue;
    }

    // Exhume: "Put N Card(s) from your Exhaust to your Hand"
    if (/Put \d+ Cards? from your Exhaust to your Hand/i.test(p)) {
      if (combatState.exhaustPile.length > 0) {
        combatState._pendingCardPick = { action: 'fromexhaust', pile: 'exhaust', count: 1 };
      } else {
        addLog('Exhume: exhaust pile is empty', 'info');
      }
      continue;
    }

    // Fiend Fire: "Exhaust All Cards in Hand" (count for subsequent damage)
    if (/Exhaust All Cards in Hand/i.test(p)) {
      const toExhaust = [...combatState.hand];
      combatState.hand = [];
      toExhaust.forEach(c => {
        combatState.exhaustPile.push(c);
        onCardExhausted(c);
      });
      combatState._exhaustedHandCount = toExhaust.length;
      if (toExhaust.length > 0) addLog(`${card.name}: Exhausted ${toExhaust.length} card(s) from Hand`, 'info');
      continue;
    }

    // Fiend Fire: "Deal NxX Dmg where X is equal to the amount of Cards Exhausted"
    const fiendFireM = p.match(/Deal (\d+)[xX]X Dmg (Melee|Ranged) where X is equal to the amount of Cards Exhausted/i);
    if (fiendFireM) {
      const dmgPer = parseInt(fiendFireM[1]);
      const isFiendRanged = fiendFireM[2].toLowerCase() === 'ranged';
      const ffAddons = isFiendRanged ? ['ranged'] : ['melee'];
      const exhaustedCount = combatState._exhaustedHandCount || 0;
      let ffDmg = dmgPer + (player.statuses['power'] || 0);
      if (player.statuses['weak']) ffDmg = Math.floor(ffDmg * 0.75);
      const ffTargets = isAoECard
        ? combatState.enemies.filter(e => e.health > 0)
        : (target ? [target] : combatState.enemies.filter(e => e.health > 0).slice(0, 1));
      ffTargets.forEach(t => {
        for (let i = 0; i < exhaustedCount; i++) dealDamage(t, ffDmg, ffAddons);
      });
      combatState._exhaustedHandCount = 0;
      addLog(`Fiend Fire: ${ffDmg}×${exhaustedCount} = ${ffDmg * exhaustedCount} dmg`, 'success');
      continue;
    }

    // Gain Double Power (Limit Break)
    if (/Gain Double Power/i.test(p)) {
      const currentPow = player.statuses['power'] || 0;
      player.statuses['power'] = currentPow * 2;
      addLog(`Limit Break: Power ${currentPow} → ${player.statuses['power']}`, 'success');
      continue;
    }

    // Juggernaut: "Whenever you Gain Block, Deal N Dmg Melee to a random enemy"
    const juggernautRegM = p.match(/Whenever you Gain Block, Deal (\d+) Dmg Melee to a random enemy/i);
    if (juggernautRegM) {
      player.statuses['juggernaut'] = parseInt(juggernautRegM[1]);
      addLog(`Juggernaut: will deal ${player.statuses['juggernaut']} Melee dmg on block gain`, 'success');
      continue;
    }

    // Gain N [Vulnerable/Weak/Frail/...] on player (self-inflicted debuff, e.g. Berserk)
    const gainSelfDebuffM = p.match(/Gain (\d+) (Vulnerable|Weak|Frail|Confused|Entangled)/i);
    if (gainSelfDebuffM) {
      const stacks = parseInt(gainSelfDebuffM[1]);
      const key = gainSelfDebuffM[2].toLowerCase();
      player.statuses[key] = (player.statuses[key] || 0) + stacks;
      addLog(`Gained ${stacks} ${gainSelfDebuffM[2]} (self)`, 'warning');
      continue;
    }

    // Demon Form: "At the start of each turn, gain X Power"
    const demonMatch = p.match(/gain (\d+) Power/i);
    if (demonMatch && lower.includes('start')) {
      const perTurn = parseInt(demonMatch[1]);
      player.statuses['power_per_turn'] = (player.statuses['power_per_turn'] || 0) + perTurn;
      addLog(`Demon Form: +${perTurn} Power each turn`, 'success');
      continue;
    }
    // Inflame / direct "Gain X Power" (immediate power gain, not per-turn)
    if (demonMatch && !lower.includes('start')) {
      const gain = parseInt(demonMatch[1]);
      player.statuses['power'] = (player.statuses['power'] || 0) + gain;
      addLog(`+${gain} Power`, 'success');
      continue;
    }

    // Assassinate: instantly kill target if its HP is at or below the threshold — deals no damage
    const assassinMatch = p.match(/(\d+) Assassinate/i);
    if (assassinMatch && target) {
      const threshold = parseInt(assassinMatch[1]);
      if (target.health <= threshold) {
        target.health = 0;
        addLog(`Assassinated ${target.name}! (${threshold} HP threshold)`, 'success');
        if (typeof onEnemyDefeated === 'function') onEnemyDefeated(target);
      } else {
        addLog(`Assassinate missed — ${target.name} has ${target.health} HP (threshold: ${threshold})`, 'info');
      }
      continue;
    }

    // Wealth — damage modifier handled as _wealthBonus pre-scan above
    if (lower.includes('wealth')) continue;

    // Heal X Health
    const healMatch = p.match(/Heal (\d+) Health/i);
    if (healMatch) {
      const hp = parseInt(healMatch[1]);
      player.health = Math.min(player.maxHealth, player.health + hp);
      window.health = player.health;
      addLog(`Healed ${hp} Health`, 'success');
      continue;
    }

    // Take X Dmg (self-damage, e.g. dice face side-effect)
    const selfDmgMatch = p.match(/Take (\d+) Dmg/i);
    if (selfDmgMatch) {
      const dmg = parseInt(selfDmgMatch[1]);
      player.health -= dmg;
      window.health = player.health;
      addLog(`Took ${dmg} damage`, 'danger');
      continue;
    }

    // Enemy loses X Power
    const enemyPowerMatch = p.match(/Enemy loses (\d+) Power/i);
    if (enemyPowerMatch && target) {
      const loss = parseInt(enemyPowerMatch[1]);
      target.statuses['power'] = Math.max(0, (target.statuses['power'] || 0) - loss);
      addLog(`${target.name} loses ${loss} Power`, 'warning');
      continue;
    }

    // Gain +X [Stat] until end of combat (stat buffs)
    const statBoostMatch = p.match(/Gain \+(\d+) (Intelligence|Strength|Dexterity|Charisma)/i);
    if (statBoostMatch) {
      const amt  = parseInt(statBoostMatch[1]);
      const stat = statBoostMatch[2].toLowerCase();
      player.statuses[stat] = (player.statuses[stat] || 0) + amt;
      addLog(`+${amt} ${statBoostMatch[2]} this combat`, 'success');
      continue;
    }

    // Fishing Weight (mark for fishing loot)
    if (lower.includes('fishing weight')) { addLog('Fishing Weight triggered', 'info'); continue; }

    // Conjure N [CardName] to Discard (Immolate etc.) — before "copy of this card" handler
    const conjureToDiscardMatch = p.match(/Conjure (\d+) (.+?) to Discard/i);
    if (conjureToDiscardMatch && !/cop(?:y|ies) of this card/i.test(conjureToDiscardMatch[2])) {
      const cDCount = parseInt(conjureToDiscardMatch[1]);
      const cDName  = conjureToDiscardMatch[2].trim();
      const cDTpl   = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.find(c => c.name.toLowerCase() === cDName.toLowerCase()) : null;
      if (cDTpl) {
        for (let i = 0; i < cDCount; i++) {
          combatState.discardPile.push({ ...cDTpl, _uid: `conjure_discard_${Date.now()}_${i}` });
        }
        addLog(`Conjured ${cDCount}x ${cDTpl.name} to Discard`, 'info');
      } else {
        addLog(`Conjure to Discard: "${cDName}" not found`, 'warning');
      }
      continue;
    }

    // Conjure N copy/copies of this card to Discard (Anger)
    if (/Conjure \d+ cop(?:y|ies) of this card to Discard/i.test(p)) {
      combatState.discardPile.push({ ...card, _uid: `copy_${Date.now()}` });
      addLog(`${card.name}: added copy to Discard`, 'info');
      continue;
    }

    // Conjure N CardName to Draw (Wild Strike: Wound to Draw)
    const conjureToDrawMatch = p.match(/Conjure (\d+) (.+?) to Draw/i);
    if (conjureToDrawMatch && !/copy of this card/i.test(conjureToDrawMatch[2])) {
      const cTDCount = parseInt(conjureToDrawMatch[1]);
      const cTDName  = conjureToDrawMatch[2].trim();
      const cTDTpl   = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.find(c => c.name.toLowerCase() === cTDName.toLowerCase()) : null;
      if (cTDTpl) {
        for (let i = 0; i < cTDCount; i++) {
          combatState.drawPile.push({ ...cTDTpl, _uid: `conjure_draw_${Date.now()}_${i}` });
        }
        addLog(`Conjured ${cTDCount}x ${cTDTpl.name} into Draw Pile`, 'info');
      } else {
        addLog(`Conjure to Draw: card "${cTDName}" not found`, 'warning');
      }
      continue;
    }

    // Conjure N CardName to Hand — explicit hand destination (Cloak and Dagger, etc.)
    const conjureToHandMatch = p.match(/Conjure (\d+) (.+?) to Hand/i);
    if (conjureToHandMatch && !/cop(?:y|ies) of that card/i.test(conjureToHandMatch[2]) && !/random/i.test(conjureToHandMatch[2])) {
      const cTHCount = parseInt(conjureToHandMatch[1]);
      const cTHRaw   = conjureToHandMatch[2].trim();
      const cTHName  = cTHRaw.replace(/s$/i, ''); // strip plural 's'
      const cTHTpl   = typeof CARDS_DATA !== 'undefined'
        ? CARDS_DATA.find(c => c.name.toLowerCase() === cTHName.toLowerCase()
                           || c.name.toLowerCase() === cTHRaw.toLowerCase())
        : null;
      if (cTHTpl) {
        for (let i = 0; i < cTHCount; i++) {
          combatState.hand.push({ ...cTHTpl, _uid: `conjure_hand_${Date.now()}_${i}` });
        }
        addLog(`Conjured ${cTHCount}x ${cTHTpl.name} to Hand`, 'success');
      } else {
        addLog(`Conjure to Hand: "${cTHName}" not found`, 'warning');
      }
      continue;
    }

    // Deal X Dmg Melee, where X is equal to your current Block (Body Slam)
    if (/Deal X Dmg Melee, where X is equal to your current Block/i.test(p)) {
      const blockDmg = player.block || 0;
      if (target) dealDamage(target, blockDmg, ['melee']);
      addLog(`Body Slam: ${blockDmg} damage (= block)`, 'info');
      continue;
    }

    // Deal N Dmg Ranged to a Random target (Sword Boomerang)
    const sboomerangMatch = p.match(/Deal (\d+) Dmg Ranged to a Random target/i);
    if (sboomerangMatch) {
      let sbDmg = parseInt(sboomerangMatch[1]);
      const sbPower = player.statuses['power'] || 0;
      if (sbPower !== 0) sbDmg += sbPower;
      if (player.statuses['weak']) sbDmg = Math.floor(sbDmg * 0.75);
      const sbLive = combatState.enemies.filter(e => e.health > 0);
      if (sbLive.length > 0) {
        const sbHit = sbLive[Math.floor(Math.random() * sbLive.length)];
        dealDamage(sbHit, sbDmg, ['ranged']);
        combatState._lastRandomHit = { dmg: sbDmg, addons: ['ranged'] };
      }
      continue;
    }

    // Repeat N times (Sword Boomerang follow-up)
    const repeatMatch = p.match(/^Repeat (\d+) times?$/i);
    if (repeatMatch && combatState._lastRandomHit) {
      const rpts = parseInt(repeatMatch[1]);
      const { dmg: rDmg, addons: rAddons } = combatState._lastRandomHit;
      const rLive = combatState.enemies.filter(e => e.health > 0);
      for (let i = 0; i < rpts; i++) {
        if (rLive.length > 0) {
          const rHit = rLive[Math.floor(Math.random() * rLive.length)];
          dealDamage(rHit, rDmg, rAddons);
        }
      }
      delete combatState._lastRandomHit;
      continue;
    }

    // Conjure X CardName — add cards to hand (skip "Random" patterns handled below)
    const conjureMatch = p.match(/Conjure (\d+) (.+)/i);
    if (conjureMatch && !/^random\b/i.test(conjureMatch[2].trim())) {
      const count    = parseInt(conjureMatch[1]);
      const nameRaw  = conjureMatch[2].trim().replace(/s$/i, ''); // strip trailing 's' for plural
      const template = typeof CARDS_DATA !== 'undefined'
        ? CARDS_DATA.find(c => c.name.toLowerCase() === nameRaw.toLowerCase()
                             || c.name.toLowerCase() === conjureMatch[2].trim().toLowerCase())
        : null;
      if (template) {
        for (let i = 0; i < count; i++) {
          combatState.hand.push({ ...template, _uid: `conjure_${Date.now()}_${i}` });
        }
        addLog(`Conjured ${count}x ${template.name}`, 'success');
      } else {
        addLog(`Conjure: card "${nameRaw}" not found`, 'warning');
      }
      continue;
    }

    // Discard X Card(s) — queue a player card pick instead of random discard
    const discardMatch = p.match(/Discard (\d+) Cards?/i);
    if (discardMatch) {
      const count = parseInt(discardMatch[1]);
      if (combatState.hand.length > 0) {
        // Queue a pending pick; the modal will be shown after resolveCardEffect returns
        combatState._pendingCardPick = {
          action: 'discard',
          pile: 'hand',
          count: Math.min(count, combatState.hand.length)
        };
      }
      continue;
    }

    // Inflict -X Power (Disarm etc.)
    const inflictNegPowerMatch = p.match(/Inflict -(\d+) Power/i);
    if (inflictNegPowerMatch && target) {
      const loss = parseInt(inflictNegPowerMatch[1]);
      target.statuses['power'] = Math.max(0, (target.statuses['power'] || 0) - loss);
      addLog(`${target.name} loses ${loss} Power`, 'warning');
      continue;
    }

    // After Image: "Whenever you play a Card, Gain X Block"
    const afterImageMatch = p.match(/Whenever you play a Card,?\s+Gain (\d+) Block/i);
    if (afterImageMatch) {
      const amt = parseInt(afterImageMatch[1]);
      player.statuses['block_per_card_play'] = (player.statuses['block_per_card_play'] || 0) + amt;
      addLog(`After Image: +${amt} Block per card played`, 'success');
      continue;
    }

    // Noxious Fumes: "At the start of each turn, Inflict X Poison [Cleave]"
    const noxFumesMatch = p.match(/Inflict (\d+) Poison/i);
    if (noxFumesMatch && lower.includes('start')) {
      const stacks = parseInt(noxFumesMatch[1]);
      player.statuses['poison_per_turn'] = (player.statuses['poison_per_turn'] || 0) + stacks;
      addLog(`Noxious Fumes: will inflict ${stacks} Poison each turn`, 'success');
      continue;
    }

    // Doppelganger: "Gain X[+N] Next Turn Draw and Gain X[+N] Next Turn Energy"
    const doppelMatch = p.match(/Gain X(?:\+(\d+))? Next Turn Draw and Gain X(?:\+(\d+))? Next Turn Energy/i);
    if (doppelMatch) {
      const drawBonus   = doppelMatch[1] ? parseInt(doppelMatch[1]) : 0;
      const energyBonus = doppelMatch[2] ? parseInt(doppelMatch[2]) : 0;
      const totalDraw   = xValue + drawBonus;
      const totalEnergy = xValue + energyBonus;
      addSeparateStatus(player, 'next_turn_draw',   totalDraw);
      addSeparateStatus(player, 'next_turn_energy', totalEnergy);
      addLog(`Doppelganger: +${totalDraw} Next Turn Draw, +${totalEnergy} Next Turn Energy`, 'success');
      continue;
    }

    // "Gain +N Next Turn Energy" (Outmaneuver, Flying Knee, etc.)
    const nextTurnEnergyMatch = p.match(/Gain \+?(\d+) Next Turn Energy/i);
    if (nextTurnEnergyMatch) {
      const gain = parseInt(nextTurnEnergyMatch[1]);
      addSeparateStatus(player, 'next_turn_energy', gain);
      addLog(`+${gain} Next Turn Energy`, 'success');
      continue;
    }

    // "Gain +N Next Turn Draw"
    const nextTurnDrawMatch = p.match(/Gain \+?(\d+) Next Turn Draw/i);
    if (nextTurnDrawMatch) {
      const gain = parseInt(nextTurnDrawMatch[1]);
      addSeparateStatus(player, 'next_turn_draw', gain);
      addLog(`+${gain} Next Turn Draw`, 'success');
      continue;
    }

    // Accuracy: "Shivs deal +N Dmg" — store permanent shiv bonus for this combat
    const accuracyMatch = p.match(/Shivs? deal \+?(\d+) Dmg/i);
    if (accuracyMatch) {
      const bonus = parseInt(accuracyMatch[1]);
      player.statuses['shiv_damage_bonus'] = (player.statuses['shiv_damage_bonus'] || 0) + bonus;
      addLog(`Accuracy: Shivs deal +${bonus} more damage`, 'success');
      continue;
    }

    // Scaling cards: "Increase the damage of ALL X cards by N this combat"
    // (e.g. Claw: each play raises all Claw damage by 2)
    const scalingMatch = p.match(/Increase the damage of ALL (.+?) cards? by \+?(\d+) this combat/i);
    if (scalingMatch) {
      const scaledCardName = scalingMatch[1].trim();
      const increment = parseInt(scalingMatch[2]);
      if (!combatState._scalingCounters) combatState._scalingCounters = {};
      combatState._scalingCounters[scaledCardName] = (combatState._scalingCounters[scaledCardName] || 0) + increment;
      addLog(`${scaledCardName} damage +${increment} (total bonus: +${combatState._scalingCounters[scaledCardName]})`, 'success');
      continue;
    }

    // Heel Hook: "If the target has [Status], [effect]"
    const conditionalMatch = p.match(/If the target has (\w+),?\s+(.+)/i);
    if (conditionalMatch && target) {
      const statusKey = conditionalMatch[1].toLowerCase();
      if ((target.statuses[statusKey] || 0) > 0) {
        // Resolve the conditional effect string (split by " and " for compound effects)
        const effects = conditionalMatch[2].split(/ and /i);
        for (const eff of effects) {
          resolveCardEffect({ ...card, description: eff.trim(), type: 'Skill', isStatusCard: false }, target, options);
        }
      }
      continue;
    }

    // Bane: "If the target has Poison, deal NxM Dmg instead"
    const baneMatch = p.match(/If the target has (\w+),\s+deal (\d+)[xX](\d+) Dmg(?: Melee| Ranged)? instead/i);
    if (baneMatch && target) {
      const statusKey = baneMatch[1].toLowerCase();
      if ((target.statuses[statusKey] || 0) > 0) {
        const dmgBase = parseInt(baneMatch[2]);
        const times   = parseInt(baneMatch[3]);
        let dmg = dmgBase;
        const pp = player.statuses['power'] || 0;
        if (pp !== 0) dmg += pp;
        if (player.statuses['weak']) dmg = Math.floor(dmg * 0.75);
        if (combatState._scalingCounters && combatState._scalingCounters[card.name]) dmg += combatState._scalingCounters[card.name];
        for (let t = 0; t < times; t++) dealDamage(target, dmg);
        addLog(`${card.name}: ${statusKey} triggered — ${dmg}x${times} = ${dmg * times} dmg`, 'success');
      }
      continue;
    }

    // Dodge and Roll: "Gain Next Turn Block equal to Block Gained"
    if (/Gain Next Turn Block equal to Block Gained/i.test(p)) {
      const lastBlockGain = card._lastBlockGain || 0;
      if (lastBlockGain > 0) {
        addSeparateStatus(player, 'next_turn_block', lastBlockGain);
        addLog(`Dodge and Roll: +${lastBlockGain} Block next turn!`, 'success');
      }
      continue;
    }

    // Second Wind / Sever Soul: "Exhaust all non-Attack Cards in Hand"
    if (/Exhaust all non-Attack Cards in Hand/i.test(p)) {
      const toExhaust = combatState.hand.filter(c => (c.type || '').toLowerCase() !== 'attack');
      toExhaust.forEach(c => {
        const idx = combatState.hand.indexOf(c);
        if (idx !== -1) combatState.hand.splice(idx, 1);
        combatState.exhaustPile.push(c);
        onCardExhausted(c);
      });
      combatState._exhaustedNonAttackCount = (combatState._exhaustedNonAttackCount || 0) + toExhaust.length;
      if (toExhaust.length > 0) addLog(`${card.name}: Exhausted ${toExhaust.length} non-Attack card(s)`, 'info');
      continue;
    }

    // Second Wind: "Gain +N Block for each Card Exhausted"
    const blockPerExhaustMatch = p.match(/Gain \+?(\d+) Block for each Card Exhausted/i);
    if (blockPerExhaustMatch) {
      const blockPer = parseInt(blockPerExhaustMatch[1]);
      const exhaustCount = combatState._exhaustedNonAttackCount || 0;
      if (exhaustCount > 0) {
        addBlock(player, blockPer * exhaustCount);
        addLog(`${card.name}: +${blockPer * exhaustCount} Block (${exhaustCount} exhausted)`, 'success');
      }
      combatState._exhaustedNonAttackCount = 0;
      continue;
    }

    // Unload: "Discard All non-Attack Cards in your hand"
    if (/Discard All non-Attack Cards in your hand/i.test(p)) {
      const toDiscard = combatState.hand.filter(c => (c.type || '').toLowerCase() !== 'attack');
      toDiscard.forEach(c => {
        const idx = combatState.hand.indexOf(c);
        if (idx !== -1) combatState.hand.splice(idx, 1);
        combatState.discardPile.push(c);
        combatState._discardedThisTurn = true;
        combatState._discardsThisTurn = (combatState._discardsThisTurn || 0) + 1;
      });
      if (toDiscard.length > 0) addLog(`${card.name}: Discarded ${toDiscard.length} non-Attack card(s)`, 'info');
      continue;
    }

    // Sneaky Strike: "If you have Discarded a Card this turn, Gain +N Energy"
    const sneakyMatch = p.match(/If you have Discarded a Card this turn,\s+Gain \+?(\d+) Energy/i);
    if (sneakyMatch) {
      if (combatState._discardedThisTurn) {
        const gain = parseInt(sneakyMatch[1]);
        player.energy += gain;
        addLog(`Sneaky Strike: +${gain} Energy (card discarded this turn)!`, 'success');
      }
      continue;
    }

    // Malaise: "Inflict -X Power and Inflict X Weak" (X = xValue)
    const malaiseMatch = p.match(/Inflict -\(X(?:\+(\d+))?\) Power and Inflict X(?:\+(\d+))? Weak/i)
                      || p.match(/Inflict -X(?:\+(\d+))? Power and Inflict X(?:\+(\d+))? Weak/i);
    if (malaiseMatch && target) {
      const bonus = parseInt(malaiseMatch[1] || malaiseMatch[2] || '0');
      const total = xValue + bonus;
      target.statuses['power'] = (target.statuses['power'] || 0) - total;
      target.statuses['weak']  = (target.statuses['weak']  || 0) + total;
      addLog(`${card.name}: -${total} Power, +${total} Weak`, 'warning');
      continue;
    }

    // Gain +N Thorns (Caltrops)
    const thornsMatch = p.match(/Gain \+?(\d+) Thorns/i);
    if (thornsMatch) {
      const t = parseInt(thornsMatch[1]);
      player.statuses['thorns'] = (player.statuses['thorns'] || 0) + t;
      addLog(`+${t} Thorns`, 'success');
      continue;
    }

    // Gain N Blur
    const blurGainMatch = p.match(/Gain (\d+) Blur/i);
    if (blurGainMatch) {
      const amt = parseInt(blurGainMatch[1]);
      player.statuses['blur'] = (player.statuses['blur'] || 0) + amt;
      addLog(`Gained ${amt} Blur`, 'success');
      continue;
    }

    // Bouncing Flask: "Inflict N Status on Random target. Repeat M times."
    const bouncingMatch = p.match(/Inflict (\d+) (\w+) on Random target\.?\s+Repeat (\d+) times?/i);
    if (bouncingMatch) {
      const amount    = parseInt(bouncingMatch[1]);
      const statusKey = bouncingMatch[2].toLowerCase();
      const repeats   = parseInt(bouncingMatch[3]);
      const totalHits = repeats + 1;
      const liveEnemies = combatState.enemies.filter(e => e.health > 0);
      if (liveEnemies.length > 0) {
        for (let i = 0; i < totalHits; i++) {
          const hit = liveEnemies[Math.floor(Math.random() * liveEnemies.length)];
          hit.statuses[statusKey] = (hit.statuses[statusKey] || 0) + amount;
          addLog(`${card.name}: ${amount} ${statusKey} → ${hit.name}`, 'warning');
        }
      }
      continue;
    }

    // Discard N Random Card(s) (All-Out Attack)
    const discardRandomMatch = p.match(/Discard (\d+) Random Cards?/i);
    if (discardRandomMatch) {
      const count = parseInt(discardRandomMatch[1]);
      for (let i = 0; i < count && combatState.hand.length > 0; i++) {
        const idx = Math.floor(Math.random() * combatState.hand.length);
        const gone = combatState.hand.splice(idx, 1)[0];
        combatState.discardPile.push(gone);
        combatState._discardedThisTurn = true;
        combatState._discardsThisTurn = (combatState._discardsThisTurn || 0) + 1;
        addLog(`${card.name}: discarded ${gone.name}`, 'info');
      }
      continue;
    }

    // Calculated Gamble: "Discard your hand, then Draw that many / X Cards..."
    if (/Discard your hand,?\s+then Draw (?:that many|X) Cards?/i.test(p)) {
      const handCount = combatState.hand.length;
      combatState.hand.forEach(c => combatState.discardPile.push(c));
      combatState.hand = [];
      if (handCount > 0) { combatState._discardedThisTurn = true; combatState._discardsThisTurn = (combatState._discardsThisTurn || 0) + handCount; }
      drawCards(handCount);
      addLog(`Calculated Gamble: discarded ${handCount}, drew ${handCount}`, 'info');
      continue;
    }

    // Catalyst: "Inflict Double/Triple Poison" — multiply target's current poison
    const catalystMatch = p.match(/Inflict (Double|Triple) Poison/i);
    if (catalystMatch && target) {
      const mult = catalystMatch[1].toLowerCase() === 'triple' ? 3 : 2;
      const cur = target.statuses['poison'] || 0;
      if (cur > 0) {
        target.statuses['poison'] = cur * mult;
        addLog(`Catalyst: Poison ${cur} → ${cur * mult}`, 'warning');
      } else {
        addLog(`Catalyst: no poison to multiply`, 'info');
      }
      continue;
    }

    // Conjure N Random [Type] to/in Hand (Distraction, Infernal Blade, White Noise)
    const conjureRandomTypeMatch = p.match(/Conjure (\d+) Random (\w+) (?:to|in) Hand/i);
    if (conjureRandomTypeMatch) {
      const count      = parseInt(conjureRandomTypeMatch[1]);
      const typeFilter = conjureRandomTypeMatch[2].toLowerCase();
      const makeFree   = /play it for free this turn/i.test(desc);
      // Draw from the player's run deck (draw + discard + hand), falling back to CARDS_DATA
      const deckCards = [
        ...(combatState.drawPile || []),
        ...(combatState.discardPile || []),
        ...(combatState.hand || []),
      ].filter(c => (c.type || '').toLowerCase() === typeFilter && !c.isStatusCard);
      const globalPool = typeof CARDS_DATA !== 'undefined'
        ? CARDS_DATA.filter(c => (c.type || '').toLowerCase() === typeFilter && !c.isStatusCard)
        : [];
      const pool = deckCards.length > 0 ? deckCards : globalPool;
      for (let i = 0; i < count; i++) {
        if (pool.length === 0) break;
        const picked = pool[Math.floor(Math.random() * pool.length)];
        const conjured = { ...picked, _uid: `conjure_rnd_${Date.now()}_${i}` };
        if (makeFree) conjured.cost = 0;
        combatState.hand.push(conjured);
        addLog(`Conjured ${conjured.name} (${typeFilter}${makeFree ? ', free' : ''})`, 'success');
      }
      continue;
    }

    // "You can play it for free this turn" — handled by the Conjure step above
    if (/You can play it for free this turn/i.test(p)) { continue; }

    // Escape Plan: "If it was a Skill, Gain +N Block"
    const escapePlanMatch = p.match(/If it was a Skill,?\s+Gain \+?(\d+) Block/i);
    if (escapePlanMatch) {
      const blockAmt = parseInt(escapePlanMatch[1]);
      if (combatState._lastDrawnCard && (combatState._lastDrawnCard.type || '').toLowerCase() === 'skill') {
        addBlock(player, blockAmt);
        addLog(`Escape Plan: drew a Skill — +${blockAmt} Block!`, 'success');
      }
      continue;
    }

    // Expertise: "Draw X Cards where X is equal to N - the amount of Cards in your Hand"
    const expertiseMatch = p.match(/Draw X Cards where X is equal to (\d+) - the amount of Cards in your Hand/i);
    if (expertiseMatch) {
      const cap = parseInt(expertiseMatch[1]);
      const toDraw = Math.max(0, cap - combatState.hand.length);
      if (toDraw > 0) drawCards(toDraw);
      addLog(`Expertise: Drew ${toDraw} card(s)`, 'success');
      continue;
    }

    // Finisher: "Deal NxX Dmg Melee where X is equal to the amount of Attacks played this turn"
    const finisherMatch = p.match(/Deal (\d+)xX Dmg (Melee|Ranged) where X is equal to the amount of Attacks played this turn/i);
    if (finisherMatch && target) {
      const dmgPer = parseInt(finisherMatch[1]);
      const isFinisherRanged = finisherMatch[2].toLowerCase() === 'ranged';
      const attackCount = (combatState.incrementals && combatState.incrementals.attacksThisTurn) || 0;
      const addons = isFinisherRanged ? ['ranged'] : ['melee'];
      for (let i = 0; i < attackCount; i++) dealDamage(target, dmgPer, addons);
      addLog(`Finisher: ${dmgPer}×${attackCount} = ${dmgPer * attackCount} dmg`, 'success');
      continue;
    }

    // Flechettes: "Deal NxX Dmg Ranged where X is equal to the amount of Skills in your Hand"
    const flechettesMatch = p.match(/Deal (\d+)xX Dmg (Melee|Ranged) where X is equal to the amount of Skills in your Hand/i);
    if (flechettesMatch && target) {
      const dmgPer = parseInt(flechettesMatch[1]);
      const isFleRanged = flechettesMatch[2].toLowerCase() === 'ranged';
      const skillCount = combatState.hand.filter(c => (c.type || '').toLowerCase() === 'skill').length;
      const addons = isFleRanged ? ['ranged'] : ['melee'];
      for (let i = 0; i < skillCount; i++) dealDamage(target, dmgPer, addons);
      addLog(`Flechettes: ${dmgPer}×${skillCount} = ${dmgPer * skillCount} dmg`, 'success');
      continue;
    }

    // Gain +N Defense (Footwork)
    const defenseGainMatch = p.match(/Gain \+?(\d+) Defense/i);
    if (defenseGainMatch) {
      const def = parseInt(defenseGainMatch[1]);
      player.statuses['defense'] = (player.statuses['defense'] || 0) + def;
      addLog(`+${def} Defense`, 'success');
      continue;
    }

    // Infinite Blades: "At the start of your turn, Conjure N Shiv(s) to Hand"
    if (/At the start of your turn,\s+Conjure (\d+) Shivs? to Hand/i.test(p)) {
      const cnt = parseInt(p.match(/Conjure (\d+)/i)[1]);
      player.statuses['shiv_per_turn'] = (player.statuses['shiv_per_turn'] || 0) + cnt;
      addLog(`Infinite Blades: +${cnt} Shiv per turn`, 'success');
      continue;
    }

    // Gain +N Buffer (Buffer card — grants the defensive Buffer status)
    const gainBufferMatch = p.match(/Gain \+?(\d+) Buffer/i);
    if (gainBufferMatch) {
      const stacks = parseInt(gainBufferMatch[1]);
      player.statuses['buffer'] = (player.statuses['buffer'] || 0) + stacks;
      addLog(`Gained ${stacks} Buffer`, 'success');
      continue;
    }

    // All for One: "Put all 0 cost Cards from Discard to Hand"
    if (/Put all 0 cost Cards? from Discard to Hand/i.test(p)) {
      const moved = [];
      for (let i = combatState.discardPile.length - 1; i >= 0; i--) {
        const c = combatState.discardPile[i];
        const effectiveCost = c._freeCost ? 0 : (c.cost || 0);
        if (effectiveCost === 0) {
          combatState.discardPile.splice(i, 1);
          combatState.hand.push(c);
          moved.push(c.name);
        }
      }
      if (moved.length > 0) addLog(`All for One: moved ${moved.length} zero-cost card(s) to hand!`, 'success');
      else addLog(`All for One: no zero-cost cards in discard`, 'info');
      continue;
    }

    // Hologram: "Put a Card from Discard to Hand"
    if (/Put a Card from (?:your )?Discard to Hand/i.test(p)) {
      if (combatState.discardPile.length > 0) {
        combatState._pendingCardPick = { action: 'tohand', pile: 'discard', count: 1 };
      }
      continue;
    }

    // Seek: "Put N Cards from your Deck to Hand"
    const seekMatch = p.match(/Put (\d+) Cards? from your Deck to Hand/i);
    if (seekMatch) {
      const count = Math.min(parseInt(seekMatch[1]), combatState.drawPile.length);
      if (count > 0) {
        combatState._pendingCardPick = { action: 'tohand', pile: 'draw', count };
      }
      continue;
    }

    // Well-Laid Plans: "Gain +N Well-Laid Plans"
    const wlpMatch = p.match(/Gain \+?(\d+) Well-Laid Plans/i);
    if (wlpMatch) {
      const stacks = parseInt(wlpMatch[1]);
      player.statuses['well_laid_plans'] = (player.statuses['well_laid_plans'] || 0) + stacks;
      addLog(`+${stacks} Well-Laid Plans`, 'success');
      continue;
    }

    // Setup: "Put 1 Card from your Hand on top of your Draw Pile. It costs 0 until played."
    if (/Put 1 Card from your Hand on top of your Draw Pile/i.test(p)) {
      if (combatState.hand.length > 0) {
        combatState._pendingCardPick = { action: 'setup', pile: 'hand', count: 1 };
      }
      continue;
    }

    // "It costs 0 until played" — handled by Setup pick action
    if (/It costs 0 until played/i.test(p)) { continue; }

    // Gain +N Burst (until end of turn)
    const burstGainMatch = p.match(/Gain \+?(\d+) Burst/i);
    if (burstGainMatch) {
      const stacks = parseInt(burstGainMatch[1]);
      player.statuses['burst'] = (player.statuses['burst'] || 0) + stacks;
      addLog(`+${stacks} Burst`, 'success');
      continue;
    }

    // Gain +N No Draw (Bullet Time)
    const noDrawMatch = p.match(/Gain \+?(\d+) No Draw/i);
    if (noDrawMatch) {
      const stacks = parseInt(noDrawMatch[1]);
      player.statuses['no_draw'] = (player.statuses['no_draw'] || 0) + stacks;
      addLog(`+${stacks} No Draw`, 'info');
      continue;
    }

    // All Cards in your Hand are free to play this turn (Bullet Time)
    if (/All Cards in your Hand are free to play this turn/i.test(p)) {
      (combatState.hand || []).forEach(c => { c._freeCost = true; });
      addLog('Bullet Time: all hand cards cost 0 this turn!', 'success');
      continue;
    }


    // Gain +N Envenom (Power card)
    const envenomGainMatch = p.match(/Gain \+?(\d+) Envenom/i);
    if (envenomGainMatch) {
      const stacks = parseInt(envenomGainMatch[1]);
      player.statuses['envenom'] = (player.statuses['envenom'] || 0) + stacks;
      addLog(`+${stacks} Envenom`, 'success');
      continue;
    }

    // Decrease the Dmg of this Card by N this combat (Glass Knife)
    const glassDecMatch = p.match(/Decrease the Dmg of this Card by (\d+) this combat/i);
    if (glassDecMatch) {
      const decrease = parseInt(glassDecMatch[1]);
      card.description = card.description.replace(/(Deal )(\d+)(x\d+ Dmg)/i, (_m, pre, num, post) =>
        pre + Math.max(0, parseInt(num) - decrease) + post
      );
      if (card.upgradedDescription) {
        card.upgradedDescription = card.upgradedDescription.replace(/(Deal )(\d+)(x\d+ Dmg)/i, (_m, pre, num, post) =>
          pre + Math.max(0, parseInt(num) - decrease) + post
        );
      }
      addLog(`${card.name}: base damage -${decrease}`, 'info');
      continue;
    }

    // Can only be played if draw pile is empty (Grand Finale condition text — skip)
    if (/Can only be played if there are no cards in your draw pile/i.test(p)) { continue; }

    // Choose a Card. Next turn, Conjure N copies of that Card to your Hand. (Nightmare)
    const nightmarePickMatch = p.match(/Choose a Card\. Next turn, Conjure (\d+) copies of that Card to your Hand/i);
    if (nightmarePickMatch) {
      const nc = parseInt(nightmarePickMatch[1]);
      if (combatState.hand.length > 0) {
        combatState._pendingCardPick = { action: 'nightmare', pile: 'hand', count: 1, _nightmareCount: nc };
      }
      continue;
    }

    // Gain +N Double Damage (Phantasmal Killer)
    const doubleDmgGainMatch = p.match(/Gain \+?(\d+) Double Damage/i);
    if (doubleDmgGainMatch) {
      const stacks = parseInt(doubleDmgGainMatch[1]);
      player.statuses['double_damage'] = (player.statuses['double_damage'] || 0) + stacks;
      addLog(`+${stacks} Double Damage`, 'success');
      continue;
    }

    // Discard your Hand, then Conjure X [Upgraded] Shivs (Storm of Steel)
    if (/Discard your Hand, then Conjure X (Upgraded )?Shivs/i.test(p)) {
      const handCards = [...combatState.hand];
      const handCount = handCards.length;
      combatState.hand = [];
      handCards.forEach(c => combatState.discardPile.push(c));
      combatState._discardedThisTurn = true;
      combatState._discardsThisTurn = (combatState._discardsThisTurn || 0) + handCount;
      const shivTemplate = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.find(c => c.name === 'Shiv') : null;
      if (shivTemplate) {
        const isUpgradedShiv = /Upgraded Shivs/i.test(p);
        for (let i = 0; i < handCount && combatState.hand.length < HAND_SIZE_LIMIT; i++) {
          const shiv = { ...shivTemplate, _uid: `sos_${Date.now()}_${i}` };
          if (isUpgradedShiv && shivTemplate.upgradedDescription) {
            shiv.upgraded = true;
            shiv.description = shivTemplate.upgradedDescription;
            if (shivTemplate.upgradedCost !== undefined && shivTemplate.upgradedCost !== null) shiv.cost = shivTemplate.upgradedCost;
          }
          combatState.hand.push(shiv);
        }
      }
      addLog(`Storm of Steel: discarded ${handCount}, conjured ${handCount} Shivs`, 'success');
      continue;
    }

    // At the start of your turn, Draw N Card and Discard N Card (Tools of the Trade)
    if (/At the start of your turn, Draw \d+ Card and Discard \d+ Card/i.test(p)) {
      player.statuses['tools_of_trade'] = 1;
      addLog('Tools of the Trade activated', 'success');
      continue;
    }

    // Gain +N Intangible (Wraith Form)
    const intangibleMatch = p.match(/Gain \+?(\d+) Intangible/i);
    if (intangibleMatch) {
      const stacks = parseInt(intangibleMatch[1]);
      player.statuses['intangible'] = (player.statuses['intangible'] || 0) + stacks;
      addLog(`+${stacks} Intangible`, 'success');
      continue;
    }

    // At the start of the turn, Lose 1 Defense (Wraith Form passive)
    if (/At the start of the turn, Lose 1 Defense/i.test(p)) {
      player.statuses['wraith_form'] = 1;
      addLog('Wraith Form: Defense will erode each turn', 'warning');
      continue;
    }

    // Gain 1 Random Potion Item (Alchemize)
    if (/Gain 1 Random Potion Item/i.test(p)) {
      if (typeof ITEMS_DATA !== 'undefined') {
        const potions = ITEMS_DATA.filter(i => i.tags && i.tags.includes('potion'));
        if (potions.length > 0) {
          const potion = potions[Math.floor(Math.random() * potions.length)];
          if (typeof acquireItem === 'function') {
            acquireItem(potion);
          } else if (typeof window.inventory !== 'undefined') {
            window.inventory.push({ ...potion, quantity: 1 });
          }
          addLog(`Alchemize: gained ${potion.name}!`, 'success');
        }
      }
      continue;
    }

    // Until the end of the turn, Gain +N Power (Flex)
    const flexMatch = p.match(/Until the end of the turn, Gain \+?(\d+) Power/i);
    if (flexMatch) {
      const fGain = parseInt(flexMatch[1]);
      player.statuses['power'] = (player.statuses['power'] || 0) + fGain;
      combatState._flexPower = (combatState._flexPower || 0) + fGain;
      addLog(`Flex: +${fGain} Power until end of turn`, 'success');
      continue;
    }

    // Play the top card of your Draw Pile and Exhaust it (Havoc)
    if (/Play the top card of your Draw Pile and Exhaust it/i.test(p)) {
      if (combatState.drawPile.length > 0) {
        const topCard = combatState.drawPile.pop();
        addLog(`Havoc: playing ${topCard.name}...`, 'info');
        // For attack cards, auto-target a random living enemy
        const havocTarget = (topCard.type || '').toLowerCase() === 'attack'
          ? (combatState.enemies.filter(e => e.health > 0)[0] || null)
          : null;
        resolveCardEffect(topCard, havocTarget, {});
        combatState.exhaustPile.push(topCard);
        addLog(`Havoc: exhausted ${topCard.name}`, 'info');
      }
      continue;
    }

    // Put a Card from your Discard on the top of the Draw Pile (Headbutt)
    if (/Put a Card from your Discard on the top of the Draw Pile/i.test(p)) {
      if (combatState.discardPile.length > 0) {
        combatState._pendingCardPick = { action: 'topdraw', pile: 'discard', count: 1 };
      }
      continue;
    }

    // Put a Card from your Hand on the top of the Draw Pile (Warcry)
    if (/Put a Card from your Hand on the top of the Draw Pile/i.test(p)) {
      if (combatState.hand.length > 0) {
        combatState._pendingCardPick = { action: 'topdraw', pile: 'hand', count: 1 };
      }
      continue;
    }

    // Power affects this card xN times (Heavy Blade — handled by pre-scan, skip)
    if (/Power affects this card x\d+ times?/i.test(p)) { continue; }

    // Deals N additional damage for all Cards that contain "Strike" (Perfected Strike)
    const perfectedMatch = p.match(/Deals (\d+) additional damage for All of your Cards that contain/i);
    if (perfectedMatch) {
      const bonusPer = parseInt(perfectedMatch[1]);
      const allDeckCards = [
        ...(combatState.drawPile || []),
        ...(combatState.hand || []),
        ...(combatState.discardPile || []),
        ...(combatState.exhaustPile || [])
      ];
      const strikeCount = allDeckCards.filter(c => /strike/i.test(c.name)).length;
      if (strikeCount > 0 && target) {
        const bonusDmg = bonusPer * strikeCount;
        dealDamage(target, bonusDmg, ['melee']);
        addLog(`Perfected Strike: +${bonusDmg} bonus (${strikeCount} Strike cards)`, 'success');
      }
      continue;
    }

    // Upgrade a Card in your hand for the rest of combat (Armaments non-upgraded)
    if (/Upgrade a Card in your hand for the rest of combat/i.test(p)) {
      if (combatState.hand.length > 0) {
        combatState._pendingCardPick = { action: 'upgrade', pile: 'hand', count: 1 };
      }
      continue;
    }

    // Upgrade all Cards in your hand for the rest of combat (Armaments upgraded)
    if (/Upgrade all Cards in your hand for the rest of combat/i.test(p)) {
      combatState.hand.forEach(c => {
        if (!c.upgraded && c.upgradedDescription) {
          c.upgraded = true;
          c.description = c.upgradedDescription;
          if (c.upgradedCost !== null && c.upgradedCost !== undefined) c.cost = c.upgradedCost;
        }
      });
      addLog('Armaments: upgraded all hand cards!', 'success');
      continue;
    }

    // Exhaust N Card(s) — player picks from hand (Burning Pact; not random, not "in your Hand")
    if (/Exhaust \d+ Cards?/i.test(p) && !/random/i.test(lower) && !/in your hand/i.test(lower)) {
      const cntM = p.match(/Exhaust (\d+)/i);
      const cnt = cntM ? parseInt(cntM[1]) : 1;
      // Look ahead for a Draw N Cards clause in the remaining parts so we can draw AFTER exhausting
      const drawAheadM = parts.slice(parts.indexOf(p) + 1).join(' ').match(/Draw (\d+) Cards?/i);
      const drawAfter = drawAheadM ? parseInt(drawAheadM[1]) : 0;
      if (combatState.hand.length > 0) {
        combatState._pendingCardPick = { action: 'exhaust', pile: 'hand', count: Math.min(cnt, combatState.hand.length), drawAfter };
      } else if (drawAfter > 0) {
        drawCards(drawAfter);
      }
      continue;
    }

    // Exhaust a random Card in your Hand (True Grit non-upgraded) — check BEFORE generic
    if (/Exhaust a random Card in your Hand/i.test(p)) {
      if (combatState.hand.length > 0) {
        const rIdx = Math.floor(Math.random() * combatState.hand.length);
        const gone = combatState.hand.splice(rIdx, 1)[0];
        combatState.exhaustPile.push(gone);
        addLog(`True Grit: exhausted ${gone.name}`, 'info');
      }
      continue;
    }

    // Exhaust a Card in your Hand (True Grit upgraded — player chooses)
    if (/Exhaust a Card in your Hand/i.test(p)) {
      if (combatState.hand.length > 0) {
        combatState._pendingCardPick = { action: 'exhaust', pile: 'hand', count: 1 };
      }
      continue;
    }

    // Can only be played if every Card in your Hand is an Attack (Clash condition — skip)
    if (/Can only be played if every Card in your Hand is an Attack/i.test(p)) { continue; }

    // Unknown — log it
    if (lower && lower !== 'n/a') addLog(`${card.name}: ${p}`, 'info');
  }

  // Clear lifesteal flag after card resolution
  if (isLifestealCard) delete combatState._lifestealActive;

  // Power-play triggers
  if ((card.type || '').toLowerCase() === 'power') {
    const invPow = typeof window.inventory !== 'undefined' ? window.inventory : [];

    // Death Orb: deal damage to all enemies equal to number of active curses
    if (invPow.some(i => i.name === 'Death Orb')) {
      const curseCount = (typeof gameState !== 'undefined' && Array.isArray(gameState.activeCurses))
        ? gameState.activeCurses.length : 0;
      if (curseCount > 0) {
        combatState.enemies.filter(e => e.health > 0).forEach(e => dealDamage(e, curseCount, ['self']));
        addLog(`Death Orb: ${curseCount} curse damage to all enemies!`, 'warning');
      }
    }

    // Mummified Hand: a random card in hand becomes free this turn
    if (invPow.some(i => i.name === 'Mummified Hand')) {
      const hand = combatState.hand;
      if (hand && hand.length > 0) {
        const idx = Math.floor(Math.random() * hand.length);
        hand[idx]._freeCost = hand[idx].cost;
        hand[idx].cost = 0;
        addLog(`Mummified Hand: ${hand[idx].name} costs 0 this turn!`, 'success');
      }
    }
  }

  // Training card: apply permanent stat bonuses and mark for permanent destruction
  if ((card.type || '').toLowerCase() === 'training') {
    const desc = (card.upgraded ? card.upgradedDescription : card.description) || card.description || '';

    // Parse "Permanently Gain +N StatName" patterns
    const statMap = { strength: 'strength', dexterity: 'dexterity', intelligence: 'intelligence', charisma: 'charisma' };
    const permRegex = /\+(\d+)\s+(strength|dexterity|intelligence|charisma)/gi;
    let m;
    while ((m = permRegex.exec(desc)) !== null) {
      const val = parseInt(m[1]);
      const stat = m[2].toLowerCase();
      if (statMap[stat] !== undefined) {
        if (typeof window[stat] !== 'undefined') window[stat] += val;
        if (typeof gameState !== 'undefined') gameState[stat] = (gameState[stat] || 0) + val;
        addLog(`${card.name}: permanently +${val} ${stat}!`, 'success');
      }
    }

    // Runner's High: for every 10 missing health, gain +N Max Health
    if (/every 10 health/i.test(desc)) {
      const gainMatch = desc.match(/Gain \+(\d+) Max Health/i);
      const gainPerTen = gainMatch ? parseInt(gainMatch[1]) : 2;
      const missing = Math.max(0, (typeof maxHealth !== 'undefined' ? maxHealth : 0) - (typeof health !== 'undefined' ? health : 0));
      const bonus = Math.floor(missing / 10) * gainPerTen;
      if (bonus > 0 && typeof StateMutator !== 'undefined') {
        StateMutator.modifyMaxHealth(bonus, { onlyMax: true });
        addLog(`${card.name}: +${bonus} Max Health from missing health!`, 'success');
      }
    }

    // Mark for permanent destruction from deck after combat
    combatState._destroyCards = combatState._destroyCards || [];
    combatState._destroyCards.push(card.name);

    // Sync stats to gameState
    if (typeof gameState !== 'undefined') {
      ['strength', 'dexterity', 'intelligence', 'charisma'].forEach(s => {
        if (typeof window[s] !== 'undefined') gameState[s] = window[s];
      });
    }

    shouldExhaust = true; // Remove from hand (won't be shuffled back since we also destroy from deck)
  }

  return shouldExhaust;
}

/**
 * Play a card from hand.
 * @param {number} handIndex - Index in combatState.hand
 * @param {string|null} targetId - Enemy id for targeted attacks
 */
function playCard(handIndex, targetId = null) {
  if (!combatState || combatState.phase !== 'player_action') return { success: false, error: 'Not player turn' };
  if (handIndex < 0 || handIndex >= combatState.hand.length) return { success: false, error: 'Invalid hand index' };

  const card = combatState.hand[handIndex];
  if (!card) return { success: false, error: 'Card not found' };

  // Unplayable / Sly cards cannot be played directly
  if (card.cost === 'No' || (card.description || '').toLowerCase().includes('unplayable')) {
    return { success: false, error: 'This card is unplayable' };
  }

  // Compute effective cost (handles dynamic costs like Eviscerate / Masterful Stab / free cards)
  let xValue = 0;
  let cardCost = getEffectiveCost(card);
  if (card.cost === 'X') {
    xValue   = combatState.player.energy;
    cardCost = xValue;
  }

  // Confused: randomize card cost between 0 and maxEnergy
  if (combatState.player.statuses['confused'] && card.cost !== 'No') {
    cardCost = Math.floor(Math.random() * (combatState.player.maxEnergy + 1));
    addLog(`Confused! ${card.name} costs ${cardCost} energy`, 'warning');
  }

  if (combatState.player.energy < cardCost) return { success: false, error: 'Not enough energy' };

  const needsTarget = cardNeedsTarget(card);
  let target = null;
  if (needsTarget) {
    target = combatState.enemies.find(e => e.id === targetId && e.health > 0);
    if (!target) return { success: false, error: 'No valid target' };
  }

  // Deduct energy and remove from hand
  combatState.player.energy -= cardCost;
  combatState.hand.splice(handIndex, 1);
  combatState.selectedCardIndex = null;
  combatState.lastPlayedCard = card;
  // Clear transient flags (free-cost, retain) when a card is actually played
  delete card._freeCost;
  delete card._retain;

  // Incremental item tracking: update attack counters BEFORE resolveCardEffect so Pen Nib can double
  const _cardType = (card.type || '').toLowerCase();
  if (_cardType === 'attack') {
    const _incInv = typeof window.inventory !== 'undefined' ? window.inventory : [];
    combatState.incrementals = combatState.incrementals || { attacksTotal: 0, attacksThisTurn: 0 };
    combatState.incrementals.attacksTotal++;
    combatState.incrementals.attacksThisTurn++;
    // Persist run-wide attack count to gameState so it survives across combats
    if (typeof gameState !== 'undefined') gameState.runAttacks = combatState.incrementals.attacksTotal;
    // Pen Nib: every 10th attack deals double damage — flag for dealDamage
    if (combatState.incrementals.attacksTotal % 10 === 0 && _incInv.some(i => i.name === 'Pen Nib')) {
      combatState._penNibDouble = true;
    }
  }

  // Fear: lose 1 stack when a Skill card is played
  if (_cardType === 'skill' && combatState.player.statuses['fear'] > 0) {
    combatState.player.statuses['fear']--;
    if (combatState.player.statuses['fear'] <= 0) delete combatState.player.statuses['fear'];
    addLog('Fear reduced by 1 (Skill played)', 'info');
  }

  // Snapshot After Image block-per-play BEFORE resolving so a Power card
  // doesn't count its own play (the status is set during resolveCardEffect for Powers).
  const _blockPerPlay = combatState.player.statuses['block_per_card_play'] || 0;

  // Resolve effects (pass xValue for X-cost cards like Doppelganger)
  // _inCardResolution: set true so loseHealth() can trigger Rupture during card resolution
  combatState._inCardResolution = true;
  let shouldExhaust = resolveCardEffect(card, target, { xValue });

  // Double Tap: next N attack(s) are played twice — replay effects
  if (_cardType === 'attack' && combatState._doubleTap > 0) {
    combatState._doubleTap--;
    resolveCardEffect(card, target, { xValue });
    addLog(`Double Tap: ${card.name} triggered again!`, 'success');
  }

  // Duplicator: weapon attack cards hit an extra time
  if (_cardType === 'attack' && card.tags && card.tags.includes('weapon')) {
    const _dupInv = typeof inventory !== 'undefined' ? inventory : [];
    if (_dupInv.some(i => i.name === 'Duplicator')) {
      resolveCardEffect(card, target, { xValue });
      addLog(`Duplicator: ${card.name} hit an extra time!`, 'success');
    }
  }

  // Corruption: Skills are exhausted when played
  if (combatState.player.statuses && combatState.player.statuses['corruption'] && _cardType === 'skill') {
    shouldExhaust = true;
  }

  // Burst: if player played a Skill and has burst stacks, replay the card's effects once
  if (_cardType === 'skill' && combatState.player.statuses['burst'] > 0) {
    combatState.player.statuses['burst']--;
    if (combatState.player.statuses['burst'] <= 0) delete combatState.player.statuses['burst'];
    resolveCardEffect(card, target, { xValue });
    addLog(`Burst: ${card.name} triggered again!`, 'success');
  }

  // Choked: each card play deals X direct damage to the choked enemy
  combatState.enemies.filter(e => e.health > 0 && e.statuses['choked']).forEach(e => {
    const chokeDmg = e.statuses['choked'];
    e.health -= chokeDmg;
    addLog(`${e.name} takes ${chokeDmg} damage from Choked!`, 'danger');
  });

  // Post-play incremental triggers for attack cards
  if (_cardType === 'attack') {
    const _incInv = typeof window.inventory !== 'undefined' ? window.inventory : [];
    const _at = combatState.incrementals.attacksTotal;
    const _att = combatState.incrementals.attacksThisTurn;
    combatState._penNibDouble = false; // clear double-damage flag
    // Nunchaku: every 10 attacks → +1 Energy
    if (_at % 10 === 0 && _incInv.some(i => i.name === 'Nunchaku')) {
      combatState.player.energy++;
      addLog('Nunchaku: +1 Energy!', 'success');
    }
    // Shuriken: every 3 attacks this turn → +1 Power
    if (_att % 3 === 0 && _incInv.some(i => i.name === 'Shuriken')) {
      combatState.player.statuses['power'] = (combatState.player.statuses['power'] || 0) + 1;
      addLog('Shuriken: +1 Power!', 'success');
    }
    // Ornamental Fan: every 4 attacks this turn → +4 Block
    if (_att % 4 === 0 && _incInv.some(i => i.name === 'Ornamental Fan')) {
      addBlock(combatState.player, 4);
      addLog('Ornamental Fan: +4 Block!', 'success');
    }
    // Rage: whenever an Attack is played this turn, gain block
    if (combatState._rageBlock) {
      addBlock(combatState.player, combatState._rageBlock);
      addLog(`Rage: +${combatState._rageBlock} Block`, 'success');
    }
  }

  // Pain (curse card): if Pain is in hand while another card is played, lose 1 Health
  if (!card.isCurse && (card.type || '').toLowerCase() !== 'curse') {
    const painInHand = combatState.hand.some(c => c.name === 'Pain' && (c.isCurse || (c.type || '').toLowerCase() === 'curse'));
    if (painInHand) {
      loseHealth(1);
      addLog('Pain: Lost 1 Health', 'danger');
    }
  }
  combatState._inCardResolution = false;

  // Route to appropriate pile
  if (shouldExhaust) {
    combatState.exhaustPile.push(card);
    addLog(`${card.name} exhausted`, 'info');
    onCardExhausted(card); // Fire Dark Embrace and similar on-exhaust triggers
  } else if (card.type === 'Power') {
    combatState.powers.push(card);
    addLog(`${card.name} activated`, 'success');
  } else {
    combatState.discardPile.push(card);
  }

  // After Image: gain block for every card played, using the pre-play snapshot so
  // playing After Image itself does not count (block_per_card_play is 0 before the Power resolves).
  if (_blockPerPlay > 0) {
    addBlock(combatState.player, _blockPerPlay);
  }

  addLog(`Played ${card.name}`, 'info');

  // Check victory
  const allDead = combatState.enemies.every(e => e.health <= 0);
  if (allDead) {
    combatState.phase = 'victory';
    addLog('Victory!', 'success');
    return { success: true, phase: 'victory' };
  }

  // Show card picker modal if a pending pick was queued (e.g., "Discard 1 Card")
  if (combatState._pendingCardPick) {
    const pick = combatState._pendingCardPick;
    combatState._pendingCardPick = null;
    if (typeof window.showCardPickerModal === 'function') {
      window.showCardPickerModal(pick);
    }
  }

  return { success: true };
}

/**
 * Called whenever a card is exhausted (from engine routing or UI picker).
 * Fires Dark Embrace ("whenever a card is exhausted, draw X") and similar triggers.
 */
function onCardExhausted(card) {
  if (!combatState || !combatState.player) return;
  const player = combatState.player;
  // Dark Embrace: draw X cards whenever any card is exhausted
  if (player.statuses && player.statuses['dark_embrace'] && !combatState._darkEmbraceFiring) {
    const draws = player.statuses['dark_embrace'];
    combatState._darkEmbraceFiring = true;
    drawCards(draws);
    addLog(`Dark Embrace: drew ${draws} card(s)`, 'success');
    combatState._darkEmbraceFiring = false;
  }
  // Feel No Pain: gain block whenever any card is exhausted
  if (player.statuses && player.statuses['feel_no_pain']) {
    addBlock(player, player.statuses['feel_no_pain']);
    addLog(`Feel No Pain: +${player.statuses['feel_no_pain']} Block`, 'success');
  }
  // Sentinel: "If this Card is Exhausted, Gain +N Energy"
  if (card && card.description) {
    const sentinelM = card.description.match(/If this Card is Exhausted, Gain \+?(\d+) Energy/i);
    if (sentinelM) {
      const energyGain = parseInt(sentinelM[1]);
      player.energy += energyGain;
      addLog(`Sentinel: +${energyGain} Energy`, 'success');
    }
  }
}

// ============== PENDING DICE SYSTEM ==============

/**
 * Add a pending die entry after rolling a Dice-type card.
 * Called by the UI after the 3D animation resolves.
 * @param {string} cardName - Name of the die card rolled
 * @param {number} faceIndex - 0-based index of the rolled face
 * @returns {Object} The new pending entry
 */
function addPendingDie(cardName, faceIndex) {
  if (!combatState) return null;

  const diceDef = (typeof DICE_DATA !== 'undefined' ? DICE_DATA : []).find(d => d.name === cardName);
  if (!diceDef) return null;

  const baseFace = diceDef.faces[faceIndex];
  if (!baseFace) return null;

  // Check if this face was made blank by Single Use
  const suKey = cardName + '_' + faceIndex;
  const isBlankFromSU = !!(combatState._usedSingleUseFaces && combatState._usedSingleUseFaces[suKey]);

  const face = isBlankFromSU ? { ...baseFace, text: '—', isBlank: true, effects: [] } : { ...baseFace };

  // Apply Druid scaling bonus to the effective value in each effect
  const druidBonus = (combatState._druidScaling && combatState._druidScaling[suKey]) || 0;
  let scaledEffects = face.effects || [];
  if (druidBonus > 0 && (face.addons || []).includes('druid')) {
    scaledEffects = scaledEffects.map(eff => ({ ...eff, value: (eff.value || 0) + druidBonus }));
  }

  const entry = {
    id: 'pd_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6),
    cardName,
    faceIndex,
    face: { ...face, effects: scaledEffects },
    scalingKey: suKey
  };

  combatState.pendingDice.push(entry);

  // Cantrip: auto-fire to a random preferred target immediately; tile STAYS in panel for manual use
  if (!face.isBlank && (face.addons || []).includes('cantrip')) {
    _applyPendingDieFaceEffects(entry, null, true);
    addLog(`${cardName}: Cantrip triggered automatically!`, 'info');
  }

  return entry;
}

/**
 * Apply the effects of a pending die face.
 * Internal helper; also called by usePendingDie.
 * @param {Object} entry - The pending die entry
 * @param {string|null} targetId - Enemy target id (for damage effects); null picks randomly
 * @param {boolean} cantripMode - If true, picks random targets without removing the entry
 */
function _applyPendingDieFaceEffects(entry, targetId, cantripMode) {
  if (!combatState) return;
  const face = entry.face;
  if (face.isBlank || !face.effects || face.effects.length === 0) return;

  const player = combatState.player;
  const livingEnemies = combatState.enemies.filter(e => e.health > 0);

  for (const eff of face.effects) {
    const move = (eff.move || '').toLowerCase();
    const val  = eff.value || 0;
    const addons = eff.addons || [];
    const isCleave = addons.some(a => a.toLowerCase() === 'cleave');
    const isMelee  = addons.some(a => a.toLowerCase() === 'melee');

    if (move === 'dmg') {
      // Resolve damage target(s)
      let targets = [];
      if (isCleave) {
        targets = livingEnemies;
      } else {
        const t = targetId ? livingEnemies.find(e => e.id === targetId) : null;
        const picked = t || (livingEnemies.length > 0 ? livingEnemies[Math.floor(Math.random() * livingEnemies.length)] : null);
        if (picked) targets = [picked];
      }
      for (const tgt of targets) {
        const power = player.statuses['power'] || 0;
        const weak  = player.statuses['weak'] ? Math.ceil(val * 0.25) : 0;
        const finalDmg = Math.max(0, val + power - weak);
        if (typeof dealDamage === 'function') {
          dealDamage(tgt, finalDmg, isMelee ? 'melee' : 'ranged');
        } else {
          tgt.health = Math.max(0, tgt.health - Math.max(0, finalDmg - (tgt.block || 0)));
          tgt.block  = Math.max(0, (tgt.block || 0) - finalDmg);
        }
        addLog(`${entry.cardName}: ${tgt.name} takes ${finalDmg} damage`, 'success');
      }
    } else if (move === 'block') {
      addBlock(player, val);
      addLog(`${entry.cardName}: +${val} Block`, 'info');
    } else if (move === 'heal') {
      player.health = Math.min(player.maxHealth, player.health + val);
      if (typeof window !== 'undefined') window.health = player.health;
      addLog(`${entry.cardName}: +${val} Health`, 'success');
    } else if (move === 'mana') {
      player.mana = Math.min(player.maxMana || 99, (player.mana || 0) + val);
      addLog(`${entry.cardName}: +${val} Mana`, 'info');
    } else if (move === 'reroll') {
      player.rerolls = (player.rerolls || 0) + val;
      if (typeof window !== 'undefined') window.reroll = player.rerolls;
      addLog(`${entry.cardName}: +${val} Reroll`, 'info');
    } else if (move === 'pain') {
      if (typeof loseHealth === 'function') {
        loseHealth(val);
      } else {
        player.health = Math.max(0, player.health - val);
        if (typeof window !== 'undefined') window.health = player.health;
      }
      addLog(`${entry.cardName}: took ${val} damage`, 'danger');
    } else if (move === 'cleanse') {
      if (typeof cleanseDebuffs === 'function') {
        cleanseDebuffs(player, val);
      }
      addLog(`${entry.cardName}: Cleanse ${val}`, 'info');
    } else if (move === 'get') {
      const statusKey = eff.statusKey || '';
      if (statusKey) {
        player.statuses[statusKey] = (player.statuses[statusKey] || 0) + val;
        addLog(`${entry.cardName}: +${val} ${statusKey}`, 'info');
      }
    }
  }
}

/**
 * Use a pending die by id, applying its face effects.
 * @param {string} pendingId - The pending die entry id
 * @param {string|null} targetId - Enemy target id (for damage faces)
 * @returns {Object} Result
 */
function usePendingDie(pendingId, targetId) {
  if (!combatState) return { success: false, error: 'No combat' };
  if (combatState.phase !== 'player_action') return { success: false, error: 'Not player turn' };

  const idx = combatState.pendingDice.findIndex(e => e.id === pendingId);
  if (idx < 0) return { success: false, error: 'Pending die not found' };

  const entry = combatState.pendingDice[idx];
  const face  = entry.face;

  // Remove from pending first so effects don't see it as active
  combatState.pendingDice.splice(idx, 1);

  if (!face.isBlank) {
    // Check if dmg face needs a target
    const needsTarget = (face.effects || []).some(e => e.move === 'dmg' && !(e.addons || []).some(a => a.toLowerCase() === 'cleave'));
    if (needsTarget && !targetId) {
      // Auto-pick random enemy
      const living = combatState.enemies.filter(e => e.health > 0);
      if (living.length > 0) targetId = living[Math.floor(Math.random() * living.length)].id;
    }

    _applyPendingDieFaceEffects(entry, targetId, false);

    // Single Use: mark face as consumed for this combat
    if ((face.addons || []).includes('singleUse')) {
      combatState._usedSingleUseFaces[entry.scalingKey] = true;
      addLog(`${entry.cardName}: Single Use face consumed`, 'info');
    }

    // Druid scaling: increment bonus by 3 for this face
    if ((face.addons || []).includes('druid')) {
      combatState._druidScaling[entry.scalingKey] = ((combatState._druidScaling[entry.scalingKey] || 0) + 3);
      addLog(`${entry.cardName}: Druid — this face is now +3 stronger`, 'info');
    }
  } else {
    addLog(`${entry.cardName}: blank face — nothing happens`, 'info');
  }

  // Check victory
  const allDead = combatState.enemies.every(e => e.health <= 0);
  if (allDead) {
    combatState.phase = 'victory';
    addLog('Victory!', 'success');
    return { success: true, phase: 'victory' };
  }

  return { success: true };
}

/**
 * Reroll all pending dice at once.
 * Costs 1 reroll. Each die rolls a new random face.
 * @returns {Object} Result
 */
function rerollAllPending() {
  if (!combatState) return { success: false, error: 'No combat' };
  if (combatState.phase !== 'player_action') return { success: false, error: 'Not player turn' };
  if ((combatState.player.rerolls || 0) < 1) return { success: false, error: 'No rerolls left' };
  if (combatState.pendingDice.length === 0) return { success: false, error: 'No dice to reroll' };

  combatState.player.rerolls--;
  if (typeof window !== 'undefined') window.reroll = combatState.player.rerolls;

  const newPending = [];
  for (const entry of combatState.pendingDice) {
    const diceDef = (typeof DICE_DATA !== 'undefined' ? DICE_DATA : []).find(d => d.name === entry.cardName);
    if (!diceDef) { newPending.push(entry); continue; }

    const newFaceIndex = Math.floor(Math.random() * diceDef.faces.length);
    const newEntry = addPendingDieRaw(entry.cardName, newFaceIndex);
    if (newEntry) newPending.push(newEntry);
  }

  combatState.pendingDice = newPending;
  addLog(`Rerolled all pending dice (${combatState.player.rerolls} rerolls remaining)`, 'info');
  return { success: true };
}

/**
 * Low-level helper: build a pending entry without pushing to pendingDice.
 * Used by rerollAllPending to batch-replace entries.
 */
function addPendingDieRaw(cardName, faceIndex) {
  const diceDef = (typeof DICE_DATA !== 'undefined' ? DICE_DATA : []).find(d => d.name === cardName);
  if (!diceDef) return null;
  const baseFace = diceDef.faces[faceIndex];
  if (!baseFace) return null;

  const suKey = cardName + '_' + faceIndex;
  const isBlankFromSU = !!(combatState._usedSingleUseFaces && combatState._usedSingleUseFaces[suKey]);
  const face = isBlankFromSU ? { ...baseFace, text: '—', isBlank: true, effects: [] } : { ...baseFace };

  const druidBonus = (combatState._druidScaling && combatState._druidScaling[suKey]) || 0;
  let scaledEffects = face.effects || [];
  if (druidBonus > 0 && (face.addons || []).includes('druid')) {
    scaledEffects = scaledEffects.map(eff => ({ ...eff, value: (eff.value || 0) + druidBonus }));
  }

  const entry = {
    id: 'pd_' + Date.now() + '_' + Math.random().toString(36).slice(2, 6),
    cardName, faceIndex,
    face: { ...face, effects: scaledEffects },
    scalingKey: suKey
  };

  // Handle cantrip on reroll too
  if (!face.isBlank && (face.addons || []).includes('cantrip')) {
    _applyPendingDieFaceEffects(entry, null, true);
    addLog(`${cardName}: Cantrip triggered on reroll!`, 'info');
  }

  return entry;
}

// ============== EXPORTS ==============

if (typeof window !== 'undefined') {
  window.CombatEngine = {
    initCombat,
    initCombatDeck,
    drawCards,
    playCard,
    cardNeedsTarget,
    rollPlayerDie,
    rerollPlayerDie,
    confirmDie,
    useDash,
    castSpell,
    endTurn,
    getCombatState,
    endCombat,
    addLog,
    getEffectiveCost,
    onCardExhausted,
    addPendingDie,
    usePendingDie,
    rerollAllPending
  };
}
