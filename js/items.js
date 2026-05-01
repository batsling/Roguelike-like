// ===== ITEMS.JS - Item Effects System =====
//
// This module handles:
// - Item acquisition and effect application
// - Modular item effects for easy extension
// - Item stat modifications


// ===== HELPER FUNCTIONS =====

// Create and display a notification popup
function createNotification(text, bgColor = '#8B4513', emoji = '') {
  const notification = document.createElement('div');
  notification.textContent = `${emoji} ${text}`;
  notification.style.cssText = `
    position: fixed;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    padding: 30px 50px;
    background: ${bgColor};
    color: white;
    border: 3px solid rgba(255, 255, 255, 0.3);
    border-radius: 12px;
    font-size: 24px;
    font-weight: bold;
    z-index: 10000;
    box-shadow: 0 8px 24px rgba(0,0,0,0.5);
    text-align: center;
    opacity: 0;
    transition: opacity 0.3s;
  `;
  document.body.appendChild(notification);

  setTimeout(() => notification.style.opacity = '1', 10);
  setTimeout(() => notification.style.opacity = '0', 1500);
  setTimeout(() => notification.remove(), 1800);
}

// Update a stat and sync it with gameState
function updateStat(statName, change) {
  const preChangeValue = (typeof window[statName] !== 'undefined' ? window[statName] : 0) || 0;
  const statMap = {
    strength: () => { strength += change; gameState.strength = strength; },
    dexterity: () => { dexterity += change; gameState.dexterity = dexterity; },
    intelligence: () => { intelligence += change; gameState.intelligence = intelligence; },
    charisma: () => { charisma += change; gameState.charisma = charisma; },
    dash: () => { dash += change; gameState.dash = dash; },
    reroll: () => { reroll += change; gameState.reroll = reroll; },
    skip: () => { skip += change; gameState.skip = skip; },
    discovery: () => { discovery += change; gameState.discovery = discovery; },
    fov: () => { fov += change; gameState.fov = fov; },
    luck: () => { luck += change; gameState.luck = luck; },
    block: () => {
    }
  };

  statMap[statName]?.();
  enforceRockBottom(statName, preChangeValue);
  if (typeof updateGameStats === 'function') updateGameStats();
}

const _ROCK_BOTTOM_STATS = ['strength', 'dexterity', 'intelligence', 'charisma', 'fov', 'discovery', 'luck'];

// Rock Bottom: prevent tracked stats from falling below their historical peak.
// preChangeValue is the stat's value BEFORE the current change (used to seed the floor on first call).
function enforceRockBottom(statName, preChangeValue) {
  if (!_ROCK_BOTTOM_STATS.includes(statName)) return;
  if (!inventory || !inventory.some(i => i.name === 'Rock Bottom')) return;

  if (!gameState.rockBottomBests) gameState.rockBottomBests = {};

  // Seed the floor from the pre-change value the first time this stat is tracked
  if (gameState.rockBottomBests[statName] === undefined) {
    gameState.rockBottomBests[statName] = preChangeValue;
  }

  const best = gameState.rockBottomBests[statName];
  const current = (typeof window[statName] !== 'undefined' ? window[statName] : 0) || 0;

  if (current > best) {
    gameState.rockBottomBests[statName] = current;
  } else if (current < best) {
    window[statName] = best;
    if (statName in gameState) gameState[statName] = best;
  }
}

// ===== SCALABLE PASSIVE ITEM SYSTEM =====
// This system handles items that scale with player stats and need to be recalculated

/**
 * Recalculate all scalable passive item bonuses
 * Called whenever stats that affect scalable items change (e.g., max health)
 * @returns {Object} Object containing calculated bonuses for each stat
 */
function recalculateScalablePassives() {
  const bonuses = {
    attack: 0,
    strength: 0,
    dexterity: 0,
    intelligence: 0,
    charisma: 0,
    luck: 0
  };

  // Check for Beefy Ring: +1 Attack per 20 max health
  const hasBeefyRing = inventory.some(item => item.name === 'Beefy Ring');
  if (hasBeefyRing) {
    const beefyRingBonus = Math.floor(maxHealth / 20);
    bonuses.attack += beefyRingBonus;
  }

  // Check for Focus Crystal: +1 Attack if melee weapon equipped
  const hasFocusCrystal = inventory.some(item => item.name === 'Focus Crystal');
  if (hasFocusCrystal && gameState.equippedWeapon) {
    const weaponTags = gameState.equippedWeapon.tags || [];
    const isMeleeWeapon = weaponTags.includes('melee');
    if (isMeleeWeapon) {
      bonuses.attack += 1;
    }
  }

  // Paper Bag: Charisma equals the player's highest stat
  const hasPaperBag = inventory.some(item => item.name === 'Paper Bag');
  if (hasPaperBag) {
    const baseCha = typeof charisma !== 'undefined' ? charisma : 0;
    const baseStr = typeof strength !== 'undefined' ? strength : 0;
    const baseDex = typeof dexterity !== 'undefined' ? dexterity : 0;
    const baseInt = typeof intelligence !== 'undefined' ? intelligence : 0;
    const highest = Math.max(baseStr, baseDex, baseInt, baseCha);
    if (highest > baseCha) {
      bonuses.charisma = (bonuses.charisma || 0) + (highest - baseCha);
    }
  }

  // Add more scalable passive items here as they're added to the game

  return bonuses;
}

/**
 * Get bonuses from equipped weapon
 * @returns {Object} Object containing weapon bonuses for each stat
 */
function getWeaponBonuses() {
  const bonuses = {
    attack: 0,
    strength: 0,
    dexterity: 0,
    intelligence: 0,
    charisma: 0,
    luck: 0
  };

  if (gameState.equippedWeapon && gameState.equippedWeapon.bonuses) {
    const weaponBonuses = gameState.equippedWeapon.bonuses;
    bonuses.attack += weaponBonuses.attack || 0;
    bonuses.strength += weaponBonuses.strength || 0;
    bonuses.dexterity += weaponBonuses.dexterity || 0;
    bonuses.intelligence += weaponBonuses.intelligence || 0;
    bonuses.charisma += weaponBonuses.charisma || 0;
    bonuses.luck += weaponBonuses.luck || 0;
  }

  return bonuses;
}

/**
 * Get total bonuses from all sources (scalable passives + weapon)
 * @returns {Object} Object containing total bonuses for each stat
 */
function getTotalBonuses() {
  const passiveBonuses = recalculateScalablePassives();
  const weaponBonuses = getWeaponBonuses();

  return {
    attack: passiveBonuses.attack + weaponBonuses.attack,
    strength: passiveBonuses.strength + weaponBonuses.strength,
    dexterity: passiveBonuses.dexterity + weaponBonuses.dexterity,
    intelligence: passiveBonuses.intelligence + weaponBonuses.intelligence,
    charisma: passiveBonuses.charisma + weaponBonuses.charisma,
    luck: passiveBonuses.luck + weaponBonuses.luck
  };
}

/**
 * Get the current attack stat including all bonuses
 * @returns {number} Total attack including base attack and all bonuses
 */
function getEffectiveAttack() {
  const bonuses = getTotalBonuses();
  return attack + bonuses.attack;
}

/**
 * Get effective value for any stat including bonuses
 * @param {string} statName - Name of the stat (strength, dexterity, etc.)
 * @returns {number} Total value including base stat and bonuses
 */
function getEffectiveStat(statName) {
  const bonuses = getTotalBonuses();
  const baseValue = window[statName] || 0;
  return baseValue + (bonuses[statName] || 0);
}

/**
 * Initialize weapon bonuses and level if not already present
 * @param {Object} weapon - The weapon object
 */
function initializeWeaponBonuses(weapon) {
  if (!weapon.bonuses) {
    weapon.bonuses = {
      attack: 0,
      strength: 0,
      dexterity: 0,
      intelligence: 0,
      charisma: 0,
      luck: 0
    };
  }
  // Initialize weapon level if not present
  if (!weapon.level) {
    weapon.level = 1;
  }
}

// Export scalable passive functions to global scope
window.recalculateScalablePassives = recalculateScalablePassives;
window.getWeaponBonuses = getWeaponBonuses;
window.getTotalBonuses = getTotalBonuses;
window.getEffectiveAttack = getEffectiveAttack;
window.getEffectiveStat = getEffectiveStat;
window.initializeWeaponBonuses = initializeWeaponBonuses;

// ===== ITEM EFFECTS REGISTRY =====
// Define all item effects here for easy maintenance and extension

const ITEM_EFFECTS = {
  // ===== STAT BOOST ITEMS =====

  "Ballistic Boots": {
    onAcquire: () => {
      dash += 1;
      gameState.dash = dash;
    }
  },

  "More Options": {
    onAcquire: () => {
      fov += 1;
      gameState.fov = fov;
      // Extra option in space choice is handled in game logic
    }
  },

  "Lucky Toe": {
    onAcquire: () => {
      luck += 1;
      gameState.luck = luck;
    }
  },

  "Lunch": {
    onAcquire: () => {
      StateMutator.modifyMaxHealth(5);
      StateMutator.modifyHealth(5);
    }
  },

  "D6": {
    onAcquire: () => {
      StateMutator.modifyAbility('reroll', 2);
    }
  },

  "Sunglasses": {
    onAcquire: () => {
      StateMutator.modifyStat('charisma', 2);
    }
  },

  "Oddly Smooth Stone": {
    onAcquire: () => {
      StateMutator.modifyStat('dexterity', 3);
    }
  },

  "Empty Tome": {
    onAcquire: () => {
      StateMutator.modifyStat('intelligence', 3);
    }
  },

  "Hollow Heart": {
    onAcquire: () => {
      StateMutator.modifyMaxHealth(8, { onlyMax: true });
    }
  },

  "Vajra": {
    onAcquire: () => {
      StateMutator.modifyStat('strength', 3);
    }
  },

  "Glass Eye": {
    onAcquire: () => {
      StateMutator.modifyStat('strength', 2);
      luck += 1;
      gameState.luck = luck;
    }
  },

  "Keeper's Sack": {
    onAcquire: () => {
      gold = (gold || 0) + 5;
      if (typeof gameState !== 'undefined') gameState.gold = gold;
      if (typeof updateTopBar === 'function') updateTopBar();
      if (typeof createNotification === 'function') createNotification("Keeper's Sack: +5 Gold!", '#f1c40f', '💰');
    }
  },

  // ===== ITEMS WITH TRADEOFFS =====

  "Bowler Hat": {
    onAcquire: () => {
      StateMutator.modifyStat('charisma', 6);
      StateMutator.modifyStat('dexterity', -2);
    }
  },

  "Wings": {
    onAcquire: () => {
      StateMutator.modifyStat('dexterity', 6);
      StateMutator.modifyStat('intelligence', -2);
    }
  },

  "Campfire": {
    onAcquire: () => {
      StateMutator.modifyStat('intelligence', 6);
      StateMutator.modifyStat('dexterity', -2);
    }
  },

  "Wheat": {
    onAcquire: () => {
      StateMutator.modifyStat('strength', 6);
      StateMutator.modifyStat('intelligence', -2);
    }
  },

  "Panda": {
    onAcquire: () => {
      StateMutator.modifyMaxHealth(20, { onlyMax: true });
      StateMutator.modifyStat('luck', 2);
      StateMutator.modifyStat('strength', -3);
    }
  },

  "Beefy Ring": {
    onAcquire: () => {
      // Scalable passive: +1 Attack per 10 max health
      // Effect is calculated dynamically in recalculateScalablePassives()
      // and applied in getEffectiveAttack()
    }
    // Note: This item's effect is handled by the scalable passive system
    // No direct stat modification needed on acquire
  },

  // ===== TRIGGERED ITEMS =====

  "Charm of the Vampire": {
    _lastProcessedFrame: 0, // Track last processed frame to avoid duplicate triggers
    onAcquire: () => {
      // No immediate effect on acquire
    },
    onEnemyDefeated: () => {
      // Use frame counter to only trigger once per defeat event
      const currentFrame = Date.now();
      const itemEffect = ITEM_EFFECTS["Charm of the Vampire"];
      if (currentFrame - itemEffect._lastProcessedFrame < 50) {
        return; // Already processed this defeat
      }
      itemEffect._lastProcessedFrame = currentFrame;

      // Count all copies in inventory
      const copies = inventory.filter(i => i.name === 'Charm of the Vampire').length;

      // 50% base chance; luck grants MIN-advantage (10% per luck point chance to roll twice, take lower)
      const roll = rollWithLuckAdvantage(undefined, false);

      if (roll < 0.5) {
        // Heal +1 health per copy (can't exceed max health)
        const healAmount = copies;
        const result = StateMutator.modifyHealth(healAmount);

        if (result.changed) {
          // Show notification
          setTimeout(() => {
            createNotification(`Charm of the Vampire: +${healAmount} Health!`, COLORS.SUCCESS, '🧛');
          }, 100);
        }
      }
    }
  },

  // ===== USABLE ITEMS =====

  "Scroll of Teleportation": {
    canUse: () => {
      // Can only use during game selection phase
      return gameState.phase === 'selection';
    },
    onUse: () => {
      // Teleport to a random connected game
      teleportToRandomGame();
    }
  },

  "Ride the Bus": {
    canUse: () => {
      // Can only use during game selection phase
      return gameState.phase === 'selection';
    },
    onUse: () => {
      // Teleport to a random Deckbuilder game
      teleportToRandomDeckbuilder();
    }
  },

  "Winged Boots": {
    canUse: () => {
      // Can only use during game selection phase
      return gameState.phase === 'selection';
    },
    onUse: () => {
      // Get current game's year
      const currentGameObj = games.find(g => g.name === gameState.currentGame);
      if (!currentGameObj) {
        console.error('Current game not found!');
        alert('Cannot determine current location!');
        return;
      }

      const currentYear = currentGameObj.year;

      // Show selection of 3 games from the same year
      selectedTeleport({
        numChoices: 3,
        year: currentYear,
        title: `Choose Your Destination (${currentYear})`
      });
    }
  },

  "The Poop": {
    canUse: () => {
      // Can use anytime
      return true;
    },
    onUse: () => {
      // Show game selection UI for visible connected games
      showPoopSelection();
    }
  },

  "Ventricle Razor": {
    uses: 2, // Can create 2 portals
    canUse: () => {
      // Can use anytime
      return true;
    },
    onUse: () => {
      const currentGame = gameState.currentGame;
      if (!currentGame) {
        alert('No current game to apply status to!');
        return;
      }

      // Check if already has portal status
      if (typeof hasGameStatus === 'function' && hasGameStatus(currentGame, 'portal')) {
        alert(`${currentGame} already has a portal!`);
        return;
      }

      // Check how many portals exist (for UI refresh logic)
      const existingPortals = typeof getGamesWithStatus === 'function'
        ? getGamesWithStatus('portal')
        : [];

      // Add portal status to current game
      if (typeof addGameStatus === 'function') {
        addGameStatus(currentGame, 'portal', '🌀');

        // Refresh current node to show status icon
        if (typeof updateNodeStatusIcons === 'function') {
          const currentNode = document.querySelector('.node.current');
          if (currentNode) {
            updateNodeStatusIcons(currentNode);
          }
        }

        // Show notification
        setTimeout(() => {
          createNotification(`Portal created at ${currentGame}!`, 'rgba(75, 0, 130, 0.95)', '🌀');
        }, 100);

        // Refresh the game view to add portal connections
        if (existingPortals.length > 0) {
          // Multiple portals now exist, refresh choices if we're in selection phase
          if (gameState.phase === 'selection' && typeof spawnChoices === 'function') {
            setTimeout(() => spawnChoices(), 500);
          }
        }
      }
    }
  },

  "Golden Beetle": {
    onAcquire: () => {
    },
    onCurseRemoved: () => {
      // Grant one chest

      // Show notification
      setTimeout(() => {
        createNotification('Golden Beetle: Gained a Chest!', COLORS.RARE, '🪲');
      }, 100);

      // Grant a chest (normal type by default)
      if (typeof offerItemReward === 'function') {
        setTimeout(() => {
          offerItemReward('normal');
        }, 500);
      }
    }
  },

  "Vitality Orb": {
    onAcquire: () => {
    },
    onCurseAdded: () => {
      const maxHealthResult = StateMutator.modifyMaxHealth(8, { onlyMax: true });
      if (maxHealthResult.changed) {
        setTimeout(() => {
          createNotification('Vitality Orb: +8 Max Health!', COLORS.SUCCESS, '🔮');
        }, 100);
      }
    }
  },

  "Wand of Wishing": {
    uses: 1,
    canUse: () => {
      // Can use anytime
      return true;
    },
    onUse: () => {
      // Show special item selection UI (like collection view)
      showWandOfWishingSelection();
    }
  },

  "Bear Trap Mask": {
    onAcquire: () => {
      // Combat effect (bleed_thorns) applied in combat-engine.js initCombat
    }
  },

  "Broken Window": {
    onAcquire: () => {
      // Combat effect (+3 BleedThorns, +1 Bleed to player) applied in combat-engine.js initCombat
    }
  },

  "Empty Syringe": {
    onAcquire: () => {
      // Passive effect: when inflicting Bleed or Poison, +1 extra — tracked via _emptySyringeActive in combat-engine.js
    }
  },

  "Rusty Razor": {
    onAcquire: () => {
      // Weapon: card added to deck via the weapon card system
    }
  },

  "Garlic": {
    onCombatStart: () => {
      const copies = inventory.filter(i => i.name === 'Garlic').reduce((n, i) => n + (i.quantity || 1), 0);
      if (typeof combatState !== 'undefined' && combatState && combatState.player) {
        combatState.player.statuses = combatState.player.statuses || {};
        combatState.player.statuses['Brace'] = (combatState.player.statuses['Brace'] || 0) + copies;
      }
      createNotification(`Garlic: +${copies} Brace`, '#66bb6a', '🧄');
    }
  },

  // ===== BOONS =====
  // Boons grant stat bonuses when conditions are met, verified after each run
  // They also have a 20% chance to apply a status effect to the next game

  "Boon of Hermes": {
    onAcquire: () => {
    }
    // Effect is applied in verification system
  },

  "Boon of Zeus": {
    onAcquire: () => {
    }
    // Effect is applied in verification system
  },

  "Boon of Poseidon": {
    onAcquire: () => {
    }
    // Effect is applied in verification system
  },

  "Boon of Artemis": {
    onAcquire: () => {
    }
    // Effect is applied in verification system
  },

  "Boon of Aphrodite": {
    onAcquire: () => {
    }
    // Effect is applied in verification system
  },

  "Boon of Athena": {
    onAcquire: () => {
    }
    // Effect is applied in verification system
  },

  // ===== CAVES OF QUD CYBERNETICS & MUTATIONS =====

  "Reactive Trauma Plate": {
    onAcquire: () => {
    }
    // Effect is handled in damage calculation
  },

  "Stabilizar Arm Locks": {
    onAcquire: () => {
      StateMutator.modifyStat('dexterity', 6);
    }
  },

  "Unstable Genome": {
    onAcquire: () => {
    },
    onGameBeaten: () => {
      // 33% chance to destroy this item and offer 3 random items
      const roll = Math.random();

      if (roll < 0.33) {
        // Find and remove this item from inventory
        const itemIndex = inventory.findIndex(item => item.name === 'Unstable Genome');
        if (itemIndex !== -1) {
          // Remove the item
          if (inventory[itemIndex].quantity && inventory[itemIndex].quantity > 1) {
            inventory[itemIndex].quantity--;
          } else {
            inventory.splice(itemIndex, 1);
          }
          gameState.inventory = [...inventory];


          // Set flag to show large chest in the normal reward flow
          gameState.unstableGenomeTriggered = true;

          // Show notification
          setTimeout(() => {
            createNotification('Unstable Genome mutated and was destroyed!', '#ff6b00', '🧬');
          }, 100);

          // Update UI
          if (typeof updateInventory === 'function') {
            updateInventory();
          }
        }
      }
    }
  },

  "Fire Potion": {
    uses: 1, // Single use
    canUse: () => {
      // Can only use in combat phase
      return gameState.phase === 'combat';
    },
    onUse: () => {
      const newCombatState = typeof window.CombatEngine !== 'undefined' && typeof window.CombatEngine.getCombatState === 'function'
        ? window.CombatEngine.getCombatState()
        : null;
      const oldCombatState = typeof window.CombatState !== 'undefined' && typeof window.CombatState.getCombatState === 'function'
        ? window.CombatState.getCombatState()
        : null;

      const damage = 20;

      // Helper: apply fire potion damage to a specific enemy (new combat system)
      function applyFirePotionToEnemy(cs, enemy) {
        let actualDamage = damage;
        if (enemy.block > 0) {
          const blocked = Math.min(enemy.block, damage);
          enemy.block -= blocked;
          actualDamage = damage - blocked;
        }
        enemy.health -= actualDamage;
        if (enemy.health < 0) enemy.health = 0;
        if (cs.log) cs.log.push({ message: `Fire Potion! Dealt ${actualDamage} damage to ${enemy.name}`, type: 'success' });
        if (typeof window.CombatUI !== 'undefined' && typeof window.CombatUI.updateCombatDisplay === 'function') {
          window.CombatUI.updateCombatDisplay();
        }
        if (enemy.health <= 0 && cs.enemies.every(e => e.health <= 0)) {
          cs.phase = 'victory';
          if (typeof window.CombatUI !== 'undefined' && typeof window.CombatUI.checkCombatEnd === 'function') {
            window.CombatUI.checkCombatEnd();
          }
        }
      }

      // Handle new dice combat system
      if (newCombatState && newCombatState.enemies && newCombatState.enemies.length > 0) {
        const living = newCombatState.enemies.filter(e => e.health > 0);
        if (living.length === 0) { console.error('Fire Potion: No living enemies'); return; }

        if (living.length === 1) {
          // Only one target — apply directly
          applyFirePotionToEnemy(newCombatState, living[0]);
          return;
        }

        // Multiple targets — show an overlay inside the existing combat modal
        const overlay = document.createElement('div');
        overlay.id = 'fire-potion-overlay';
        overlay.style.cssText = `
          position:absolute; inset:0; z-index:999;
          background:rgba(0,0,0,0.82);
          display:flex; align-items:center; justify-content:center;
          border-radius:inherit;
        `;

        const targetsHTML = living.map((e, idx) => `
          <button onclick="window._firePotionApply(${idx})" style="
            display:flex; align-items:center; gap:12px;
            padding:12px 20px; background:#2d2d2d; border:2px solid #e74c3c;
            border-radius:8px; color:white; cursor:pointer; font-size:14px; font-weight:bold;
            width:100%; margin-bottom:8px; transition:background 0.15s;
          " onmouseenter="this.style.background='#4a1a1a'" onmouseleave="this.style.background='#2d2d2d'">
            ${e.imageUrl ? `<img src="${e.imageUrl}" style="width:40px;height:40px;object-fit:contain;image-rendering:pixelated;" onerror="this.style.display='none'">` : ''}
            <span>${e.name}</span>
            <span style="margin-left:auto;color:#aaa;font-size:12px;">${e.health}/${e.maxHealth} HP</span>
          </button>
        `).join('');

        overlay.innerHTML = `
          <div style="padding:24px; min-width:320px; max-width:420px; background:#1a1a2e; border-radius:12px; border:1px solid #e74c3c;">
            <h3 style="color:#e74c3c; text-align:center; margin-top:0;">🔥 Fire Potion — Choose Target</h3>
            <p style="color:#aaa; text-align:center; font-size:13px; margin-bottom:16px;">Deals ${damage} damage to one enemy.</p>
            ${targetsHTML}
            <button onclick="document.getElementById('fire-potion-overlay')?.remove(); delete window._firePotionApply;" style="
              width:100%; padding:10px; background:#444; border:none; border-radius:6px;
              color:#aaa; cursor:pointer; margin-top:4px;
            ">Cancel</button>
          </div>
        `;

        window._firePotionApply = (idx) => {
          delete window._firePotionApply;
          document.getElementById('fire-potion-overlay')?.remove();
          applyFirePotionToEnemy(newCombatState, living[idx]);
        };

        const combatModal = document.getElementById('dice-combat-modal');
        const parent = combatModal ? combatModal.parentElement : document.body;
        if (parent && combatModal) {
          combatModal.style.position = 'relative';
          combatModal.appendChild(overlay);
        } else {
          document.body.appendChild(overlay);
        }
        return;
      }

      // Handle old combat system (single enemy only)
      if (oldCombatState && oldCombatState.enemy) {
        let damageResult = { healthLost: damage, blockConsumed: 0 };
        if (typeof window.CombatEffects !== 'undefined' && typeof window.CombatEffects.processDamageWithBlock === 'function') {
          damageResult = window.CombatEffects.processDamageWithBlock(oldCombatState.enemy, damage);
        } else {
          oldCombatState.enemy.health -= damage;
          if (oldCombatState.enemy.health < 0) oldCombatState.enemy.health = 0;
        }
        if (typeof window.CombatState !== 'undefined' && typeof window.CombatState.addCombatLog === 'function') {
          window.CombatState.addCombatLog(`Fire Potion! Dealt ${damageResult.healthLost} damage${damageResult.blockConsumed > 0 ? ` (${damageResult.blockConsumed} blocked)` : ''}`, 'success');
        }
        if (typeof updateCombatUI === 'function') updateCombatUI();
        if (oldCombatState.enemy.health <= 0) {
          oldCombatState.phase = 'victory';
          if (typeof window.CombatState !== 'undefined' && typeof window.CombatState.addCombatLog === 'function') {
            window.CombatState.addCombatLog(`${oldCombatState.enemy.name} defeated by Fire Potion!`, 'success');
          }
          if (typeof updateCombatUI === 'function') updateCombatUI();
        }
        return;
      }

      console.error('Fire Potion: No active combat found');
    }
  },

  // ===== NEW SLAY THE SPIRE ITEMS =====

  "Busted Crown": {
    onAcquire: () => {
      StateMutator.modifyMaxEnergy(1);
      StateMutator.modifyDiscovery(-2);
    }
  },

  "Philosopher's Stone": {
    onAcquire: () => {
      // +1 Max Energy (can be upgraded/downgraded)
      StateMutator.modifyMaxEnergy(1);
      // Note: The enemy Power effect is handled in combat initialization
    }
    // Enemy Power effect is applied in combat-engine.js when combat starts
  },

  "Meat on the Bone": {
    onAcquire: () => {
    },
    onCombatEnd: (combatState) => {
      // Trigger if health is at 50% or below max
      if (health <= maxHealth / 2) {
        // Count copies for stacking
        const copies = inventory.filter(i => i.name === 'Meat on the Bone').length;
        const healAmount = 12 * copies;

        StateMutator.modifyHealth(healAmount);

        if (typeof createNotification === 'function') {
          createNotification(`Meat on the Bone: +${healAmount} Health`, '#66bb6a', '🍖');
        }
      }
    }
  },

  "Burning Blood": {
    onCombatEnd: (combatState) => {
      const copies = inventory.filter(i => i.name === 'Burning Blood').reduce((n, i) => n + (i.quantity || 1), 0);
      const heal = 6 * copies;
      StateMutator.modifyHealth(heal);
      if (typeof createNotification === 'function') {
        createNotification(`Burning Blood: +${heal} Health`, '#e74c3c', '🩸');
      }
    }
  },

  "Ring of the Snake": {
    onCombatStart: () => {
      if (typeof drawCards === 'function') {
        drawCards(2);
        addLog('Ring of the Snake: Draw 2 extra cards!', 'success');
      }
      if (typeof createNotification === 'function') {
        createNotification('Ring of the Snake: +2 cards drawn!', '#66bb6a', '🐍');
      }
    }
  },

  "Blood Vial": {
    onAcquire: () => {
    },
    onCombatStart: () => {
      // Count copies for stacking
      const copies = inventory.filter(i => i.name === 'Blood Vial').length;
      const healAmount = 1 * copies;

      StateMutator.modifyHealth(healAmount);

      if (typeof createNotification === 'function') {
        createNotification(`Blood Vial: +${healAmount} Health`, '#66bb6a', '🩸');
      }
    }
  },

  "Focus Crystal": {
    onAcquire: () => {
      // Effect is calculated dynamically in getEffectiveAttack()
    }
  },

  "Horn Cleat": {
    onAcquire: () => {
      // Effect is applied in combat turn 2 via initCombat flag
    }
  },

  "Molten Egg": {
    onAcquire: () => {
      // Effect applied in addCardToDeck: auto-upgrades Attack cards added to deck
    }
  },

  "Toxic Egg": {
    onAcquire: () => {
      // Effect applied in addCardToDeck: auto-upgrades Skill cards added to deck
    }
  },

  "Frozen Egg": {
    onAcquire: () => {
      // Effect applied in addCardToDeck: auto-upgrades Power cards added to deck
    }
  },

  // ===== MEWGENICS USABLE ITEMS =====

  "Percs": {
    uses: 1,
    canUse: () => gameState.phase === 'combat',
    onUse: () => {
      const cs = window.CombatEngine && window.CombatEngine.getCombatState ? window.CombatEngine.getCombatState() : null;
      if (cs && cs.player) {
        cs.player.block = (cs.player.block || 0) + 10;
        if (cs.log) cs.log.push({ message: 'Percs: +10 Block!', type: 'success' });
        createNotification('Percs: +10 Block!', COLORS.SUCCESS, '💊');
      }
    }
  },

  "Roid Rage": {
    uses: 1,
    canUse: () => gameState.phase === 'combat',
    onUse: () => {
      const cs = window.CombatEngine && window.CombatEngine.getCombatState ? window.CombatEngine.getCombatState() : null;
      if (cs && cs.player) {
        cs.player.statuses['strength'] = (cs.player.statuses['strength'] || 0) + 5;
        if (cs.log) cs.log.push({ message: 'Roid Rage: +5 Strength this combat!', type: 'success' });
        createNotification('Roid Rage: +5 Strength!', COLORS.SUCCESS, '💊');
      }
    }
  },

  "Speedball": {
    uses: 1,
    canUse: () => gameState.phase === 'combat',
    onUse: () => {
      const cs = window.CombatEngine && window.CombatEngine.getCombatState ? window.CombatEngine.getCombatState() : null;
      if (cs && cs.player) {
        cs.player.statuses['dexterity'] = (cs.player.statuses['dexterity'] || 0) + 5;
        if (cs.log) cs.log.push({ message: 'Speedball: +5 Dexterity this combat!', type: 'success' });
        createNotification('Speedball: +5 Dexterity!', COLORS.SUCCESS, '💊');
      }
    }
  },

  "Brain Candy": {
    uses: 1,
    canUse: () => gameState.phase === 'combat',
    onUse: () => {
      const cs = window.CombatEngine && window.CombatEngine.getCombatState ? window.CombatEngine.getCombatState() : null;
      if (cs && cs.player) {
        cs.player.statuses['intelligence'] = (cs.player.statuses['intelligence'] || 0) + 5;
        if (cs.log) cs.log.push({ message: 'Brain Candy: +5 Intelligence this combat!', type: 'success' });
        createNotification('Brain Candy: +5 Intelligence!', COLORS.SUCCESS, '💊');
      }
    }
  },

  "Clover": {
    uses: 1,
    canUse: () => gameState.phase === 'combat',
    onUse: () => {
      const cs = window.CombatEngine && window.CombatEngine.getCombatState ? window.CombatEngine.getCombatState() : null;
      if (cs && cs.player) {
        cs.player.statuses['luck_bonus'] = (cs.player.statuses['luck_bonus'] || 0) + 5;
        if (cs.log) cs.log.push({ message: 'Clover: +5 Luck this combat!', type: 'success' });
        createNotification('Clover: +5 Luck!', COLORS.SUCCESS, '🍀');
      }
    }
  },

  "Disco Biscuit": {
    uses: 1,
    canUse: () => gameState.phase === 'combat',
    onUse: () => {
      const cs = window.CombatEngine && window.CombatEngine.getCombatState ? window.CombatEngine.getCombatState() : null;
      if (cs && cs.player) {
        cs.player.statuses['charisma'] = (cs.player.statuses['charisma'] || 0) + 5;
        if (cs.log) cs.log.push({ message: 'Disco Biscuit: +5 Charisma this combat!', type: 'success' });
        createNotification('Disco Biscuit: +5 Charisma!', COLORS.SUCCESS, '💊');
      }
    }
  },

  "Stem Cells": {
    uses: 1,
    canUse: () => gameState.phase === 'combat',
    onUse: () => {
      const cs = window.CombatEngine && window.CombatEngine.getCombatState ? window.CombatEngine.getCombatState() : null;
      if (cs && cs.player) {
        cs.player.statuses['regeneration'] = (cs.player.statuses['regeneration'] || 0) + 3;
        if (cs.log) cs.log.push({ message: 'Stem Cells: +3 Regeneration!', type: 'success' });
        createNotification('Stem Cells: +3 Regeneration!', COLORS.SUCCESS, '🧫');
      }
    }
  },

  // ===== STS: ANCHOR, BRONZE SCALES =====

  "Anchor": {
    onAcquire: () => {
      // Effect applied in combat-engine.js initCombat
    }
  },

  "Bronze Scales": {
    onAcquire: () => {
      // Effect applied in combat-engine.js initCombat
    }
  },

  // ===== STS/FOLD: TRIGGERED POWER CARDS =====

  "Death Orb": {
    onAcquire: () => {
      // Effect applied in combat-engine.js resolveCardEffect on Power play
    }
  },

  "Mummified Hand": {
    onAcquire: () => {
      // Effect applied in combat-engine.js resolveCardEffect on Power play
    }
  },

  // ===== STS: STRIKE DUMMY =====

  "Strike Dummy": {
    onAcquire: () => {
      // Effect applied in combat-engine.js resolveCardEffect on Attack play
    }
  },

  // ===== STS: PICKUP ITEMS =====

  "Whetstone": {
    onAcquire: () => {
      // Build combined pool: starter Attack cards + collected Attack cards
      const charData = (typeof PLAYER_CHARACTERS !== 'undefined' && gameState.character)
        ? PLAYER_CHARACTERS[gameState.character] : null;
      const upgradedStarting = gameState.upgradedStartingCards || {};
      const pool = [];
      // Starter deck attacks — track per-instance upgrade count
      ((charData && charData.startingDeck) || []).forEach(entry => {
        const tmpl = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.find(c => c.name === entry.cardName) : null;
        if (tmpl && (tmpl.type || '').toLowerCase() === 'attack' && tmpl.upgradedDescription) {
          const total = entry.count || 1;
          const val = upgradedStarting[entry.cardName];
          const alreadyUpgraded = typeof val === 'number' ? Math.min(val, total) : (val ? total : 0);
          const remaining = total - alreadyUpgraded;
          for (let i = 0; i < remaining; i++) pool.push({ _isStarting: true, name: tmpl.name });
        }
      });
      // Collected deck attacks
      (gameState.deck || []).forEach((c, i) => {
        if (!c.upgraded && (c.type || '').toLowerCase() === 'attack' && c.upgradedDescription)
          pool.push({ _isStarting: false, c, i });
      });
      const targets = pool.sort(() => Math.random() - 0.5).slice(0, 2);
      const names = [];
      targets.forEach(t => {
        if (t._isStarting) {
          if (!gameState.upgradedStartingCards) gameState.upgradedStartingCards = {};
          const prev = gameState.upgradedStartingCards[t.name];
          gameState.upgradedStartingCards[t.name] = (typeof prev === 'number' ? prev : 0) + 1;
          names.push(t.name);
        } else {
          t.c.upgraded = true;
          t.c.description = t.c.upgradedDescription;
          if (t.c.upgradedCost !== null && t.c.upgradedCost !== undefined) t.c.cost = t.c.upgradedCost;
          names.push(t.c.name);
        }
      });
      if (names.length > 0) {
        createNotification(`Whetstone: upgraded ${names.join(', ')}!`, COLORS.SUCCESS, '🪨');
        saveCurrentGame();
      }
    }
  },

  "War Paint": {
    onAcquire: () => {
      // Build combined pool: starter Skill cards + collected Skill cards
      const charData = (typeof PLAYER_CHARACTERS !== 'undefined' && gameState.character)
        ? PLAYER_CHARACTERS[gameState.character] : null;
      const upgradedStarting = gameState.upgradedStartingCards || {};
      const pool = [];
      // Starter deck skills — track per-instance upgrade count
      ((charData && charData.startingDeck) || []).forEach(entry => {
        const tmpl = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.find(c => c.name === entry.cardName) : null;
        if (tmpl && (tmpl.type || '').toLowerCase() === 'skill' && tmpl.upgradedDescription) {
          const total = entry.count || 1;
          const alreadyUpgraded = Math.min(upgradedStarting[entry.cardName] || 0, total);
          const remaining = total - alreadyUpgraded;
          for (let i = 0; i < remaining; i++) pool.push({ _isStarting: true, name: tmpl.name });
        }
      });
      // Collected deck skills
      (gameState.deck || []).forEach((c, i) => {
        if (!c.upgraded && (c.type || '').toLowerCase() === 'skill' && c.upgradedDescription)
          pool.push({ _isStarting: false, c, i });
      });
      const targets = pool.sort(() => Math.random() - 0.5).slice(0, 2);
      const names = [];
      targets.forEach(t => {
        if (t._isStarting) {
          if (!gameState.upgradedStartingCards) gameState.upgradedStartingCards = {};
          const prev = gameState.upgradedStartingCards[t.name];
          gameState.upgradedStartingCards[t.name] = (typeof prev === 'number' ? prev : 0) + 1;
          names.push(t.name);
        } else {
          t.c.upgraded = true;
          t.c.description = t.c.upgradedDescription;
          if (t.c.upgradedCost !== null && t.c.upgradedCost !== undefined) t.c.cost = t.c.upgradedCost;
          names.push(t.c.name);
        }
      });
      if (names.length > 0) {
        createNotification(`War Paint: upgraded ${names.join(', ')}!`, COLORS.SUCCESS, '🎨');
        saveCurrentGame();
      } else {
        createNotification('War Paint: no upgradeable Skill cards found.', COLORS.WARNING, '🎨');
      }
    }
  },

  "Old Coin": {
    onAcquire: () => {
      const gain = 100;
      window.gold = (window.gold || 0) + gain;
      if (typeof gameState !== 'undefined') gameState.gold = window.gold;
      if (typeof saveCurrentGame === 'function') saveCurrentGame();
      createNotification(`Old Coin: +${gain} Gold!`, COLORS.SUCCESS, '🪙');
    }
  },

  "Mango": {
    onAcquire: () => {
      const gain = 14;
      window.maxHealth = (window.maxHealth || 0) + gain;
      window.health    = Math.min((window.health || 0) + gain, window.maxHealth);
      if (typeof gameState !== 'undefined') {
        gameState.maxHealth = window.maxHealth;
        gameState.health    = window.health;
      }
      if (typeof saveCurrentGame === 'function') saveCurrentGame();
      createNotification(`Mango: +${gain} Max Health and +${gain} Health!`, COLORS.SUCCESS, '🥭');
    }
  },

  // Ice Cream: energy remaining at end of turn carries over to the next turn (tracked in combat engine)
  "Ice Cream": {}
};

// ===== DAMAGE REDUCTION FUNCTION =====

/**
 * Calculate damage reduction from items
 * @param {number} incomingDamage - The raw damage amount
 * @returns {number} - The reduced damage amount
 */
function calculateDamageReduction(incomingDamage) {
  return incomingDamage;
}

// ===== ITEM ACQUISITION FUNCTION =====

/**
 * Apply item effects when acquired
 * @param {Object} item - The item being acquired
 */
function applyItemEffects(item) {
  if (!item || !item.name) {
    console.warn('Invalid item:', item);
    return;
  }

  const effects = ITEM_EFFECTS[item.name];

  if (effects) {
    // Apply onAcquire effect if it exists
    if (effects.onAcquire && typeof effects.onAcquire === 'function') {
      effects.onAcquire();
    }

    // Update UI after applying effects
    updateGameStats();
    updateTopBar();
  } else {
    // No effects defined yet - this is fine for items without passive stats
  }
}

/**
 * Extract stats that an item provides from its ITEM_EFFECTS
 * @param {string} itemName - Name of the item
 * @returns {Array} Array of stat names that the item affects
 */
function getItemStats(itemName) {
  const effects = ITEM_EFFECTS[itemName];
  if (!effects || !effects.onAcquire) {
    return [];
  }

  // Convert the onAcquire function to string and parse for stat modifications
  const funcString = effects.onAcquire.toString();
  const stats = [];

  // Check for each stat type in the function body
  if (funcString.includes('strength')) stats.push('strength');
  if (funcString.includes('dexterity')) stats.push('dexterity');
  if (funcString.includes('intelligence')) stats.push('intelligence');
  if (funcString.includes('charisma')) stats.push('charisma');
  if (funcString.includes('luck')) stats.push('luck');
  if (funcString.includes('dash')) stats.push('dash');
  if (funcString.includes('reroll')) stats.push('reroll');
  if (funcString.includes('skip')) stats.push('skip');
  if (funcString.includes('discovery')) stats.push('discovery');
  if (funcString.includes('fov')) stats.push('fov');

  return stats;
}

/**
 * Extract all stat modifications from an item's ITEM_EFFECTS with their directions (positive/negative)
 * @param {string} itemName - Name of the item
 * @returns {Array} Array of stat modification objects with {stat: string, direction: number (1 or -1)}
 */
function getItemStatModifications(itemName) {
  const effects = ITEM_EFFECTS[itemName];
  if (!effects || !effects.onAcquire) {
    return [];
  }

  const funcString = effects.onAcquire.toString();
  const modifications = [];

  // Parse for modifyStat calls: modifyStat('strength', 2) or modifyStat('dexterity', -1)
  const statRegex = /modifyStat\(['"](\w+)['"]\s*,\s*(-?\d+)\)/g;
  let match;

  while ((match = statRegex.exec(funcString)) !== null) {
    const statName = match[1];
    const value = parseInt(match[2]);
    modifications.push({
      stat: statName,
      direction: value >= 0 ? 1 : -1
    });
  }

  // Parse for modifyMaxHealth calls
  const maxHealthRegex = /modifyMaxHealth\((-?\d+)\)/g;
  while ((match = maxHealthRegex.exec(funcString)) !== null) {
    const value = parseInt(match[1]);
    modifications.push({
      stat: 'maxHealth',
      direction: value >= 0 ? 1 : -1
    });
  }

  // Parse for modifyMaxEnergy calls
  const maxEnergyRegex = /modifyMaxEnergy\((-?\d+)\)/g;
  while ((match = maxEnergyRegex.exec(funcString)) !== null) {
    const value = parseInt(match[1]);
    modifications.push({
      stat: 'maxEnergy',
      direction: value >= 0 ? 1 : -1
    });
  }

  // Parse for modifyDiscovery calls
  const discoveryRegex = /modifyDiscovery\((-?\d+)\)/g;
  while ((match = discoveryRegex.exec(funcString)) !== null) {
    const value = parseInt(match[1]);
    modifications.push({
      stat: 'discovery',
      direction: value >= 0 ? 1 : -1
    });
  }

  // Parse for direct stat assignments like: strength += 2, luck += 1
  // This handles stats modified directly without StateMutator
  if (funcString.includes('luck ++') || funcString.includes('luck +=') || funcString.includes('luck = ')) {
    if (!modifications.find(m => m.stat === 'luck')) {
      modifications.push({ stat: 'luck', direction: 1 });
    }
  }

  // Special case: Calipers grants block in combat (not on acquire)
  // Allow it to be upgraded/downgraded by treating block as a modifiable stat
  if (itemName === 'Calipers') {
    modifications.push({ stat: 'block', direction: 1 });
  }

  // Special case: Philosopher's Stone - only energy is upgradeable, not the enemy Power effect
  // The parsing above will already capture maxEnergy, so we don't need to add anything here
  // The enemy Power effect is NOT a stat modification, so it won't be affected by upgrade/downgrade

  return modifications;
}

/**
 * Downgrade a specific passive item's stats
 * @param {Object} item - The item to downgrade
 * @param {number} downgradeAmount - Amount to downgrade per stat (default -1, can be -2 for stacked curses)
 * @returns {Object} Result object with success, itemName, stats array, and change
 */
function downgradePassiveItem(item, downgradeAmount = -1) {
  // Initialize modifiers if not present
  initializePassiveModifiers(item);

  // Get all stat modifications this item provides
  const statModifications = getItemStatModifications(item.name);

  // If no stat modifications found, fall back to random stat (shouldn't happen for items with effects)
  if (statModifications.length === 0) {
    console.warn(`No stat modifications found for ${item.name}, using fallback`);
    const availableStats = ['strength', 'dexterity', 'intelligence', 'charisma', 'dash', 'reroll', 'skip', 'discovery', 'fov', 'luck', 'maxHealth', 'maxEnergy', 'block'];
    const randomStat = availableStats[Math.floor(Math.random() * availableStats.length)];
    statModifications.push({ stat: randomStat, direction: 1 });
  }

  // Store the original name if not already stored
  if (!item.originalName) {
    item.originalName = item.name;
  }

  // Store the original description if not already stored
  if (!item.originalDescription) {
    item.originalDescription = item.description;
  }

  // Apply downgrade to ALL stats this item provides
  const modifiedStats = [];
  statModifications.forEach(({ stat }) => {
    // Apply the same downgrade amount to each stat uniformly
    // E.g., if item gives +2 strength, downgrade by -1 makes it +1 strength
    // If item gives -2 strength, downgrade by -1 makes it -3 strength
    const change = downgradeAmount;

    item.statModifiers[stat] += change;

    // Apply the stat change to the game state
    if (stat === 'maxHealth') {
      // Handle max health specially
      if (typeof StateMutator !== 'undefined' && typeof StateMutator.modifyMaxHealth === 'function') {
        StateMutator.modifyMaxHealth(change);
      } else {
        maxHealth += change;
        gameState.maxHealth = maxHealth;
        health = Math.min(health, maxHealth);
        gameState.health = health;
      }
    } else if (stat === 'maxEnergy') {
      // Handle max energy
      if (typeof StateMutator !== 'undefined' && typeof StateMutator.modifyMaxEnergy === 'function') {
        StateMutator.modifyMaxEnergy(change);
      } else {
        gameState.maxEnergy = (gameState.maxEnergy || 2) + change;
      }
    } else if (stat === 'discovery') {
      // Handle discovery
      if (typeof StateMutator !== 'undefined' && typeof StateMutator.modifyDiscovery === 'function') {
        StateMutator.modifyDiscovery(change);
      } else {
        discovery += change;
        gameState.discovery = discovery;
      }
    } else {
      updateStat(stat, change);
    }

    modifiedStats.push({ stat, change });
  });

  // Update the display name
  item.displayName = getPassiveDisplayName(item);

  // Update the description with modifier info
  const modifierDesc = getPassiveModifierDescription(item);
  if (modifierDesc) {
    item.description = `${item.originalDescription}\n\n[Modified: ${modifierDesc}]`;
  }

  // Show notification for all modified stats
  if (typeof createNotification === 'function') {
    const source = downgradeAmount < -1 ? 'Curse of Decay (stacked)' : 'Curse of Decay';
    const statsText = modifiedStats.map(({ stat, change }) => {
      const statDisplay = stat === 'maxHealth' ? 'Max Health' : stat.charAt(0).toUpperCase() + stat.slice(1);
      return `${statDisplay} ${change > 0 ? '+' : ''}${change}`;
    }).join(', ');
    createNotification(`${source}: ${item.originalName || item.name} - ${statsText}`, '#8b4513', '⬇️');
  }

  return {
    success: true,
    itemName: item.displayName || item.name,
    stats: modifiedStats,
    change: downgradeAmount
  };
}

/**
 * Add item to inventory and apply its effects
 * @param {Object} item - The item to add
 */
function acquireItem(item) {
  if (!item) return;

  // Create a copy of the item
  // For weapons, exclude bonuses and level to ensure each instance is independent
  const itemCopy = { ...item };
  if (item.type === 'Weapon') {
    delete itemCopy.bonuses;
    delete itemCopy.level;
  }

  // Initialize uses for Usable items
  if (itemCopy.type === 'Usable') {
    const effects = ITEM_EFFECTS[itemCopy.name];
    // Default to 1 use, or use the value from ITEM_EFFECTS
    itemCopy.uses = (effects && effects.uses) || 1;
  }

  // Weapons do NOT stack - each weapon is a separate inventory entry
  const isWeapon = itemCopy.type === 'Weapon';

  // Track which item entry was affected (for Curse of Decay logic)
  let targetItemIndex = -1;
  let wasStacked = false;

  if (isWeapon) {
    // Each copy is independent — always add a new inventory entry and a new deck card
    itemCopy.quantity = 1;
    initializeWeaponBonuses(itemCopy);
    inventory.push(itemCopy);
    targetItemIndex = inventory.length - 1;
    if (typeof CARDS_DATA !== 'undefined') {
      const weaponCard = CARDS_DATA.find(c => c.name === itemCopy.name && c.tags && c.tags.includes('weapon'));
      if (weaponCard) {
        const addFn = window.addCardToDeck || (typeof addCardToDeck !== 'undefined' ? addCardToDeck : null);
        if (addFn) {
          addFn(weaponCard);
        } else if (typeof gameState !== 'undefined') {
          if (!gameState.deck) gameState.deck = [];
          gameState.deck.push({ ...weaponCard, upgraded: false });
          if (typeof saveCurrentGame === 'function') saveCurrentGame();
        }
        if (typeof createNotification === 'function') {
          createNotification(`${weaponCard.name} card added to deck!`, '#4CAF50', '🃏');
        }
      }
    }
  } else {
    // Check if item already exists in inventory (for stacking non-weapons)
    // For items with stat modifiers (upgraded/downgraded), only stack if modifiers match exactly
    const existingItemIndex = inventory.findIndex(existingItem => {
      if (existingItem.name !== itemCopy.name) {
        return false;
      }

      // If either item has stat modifiers, check if they match exactly
      const existingHasModifiers = existingItem.statModifiers &&
        Object.values(existingItem.statModifiers).some(v => v !== 0);
      const newHasModifiers = itemCopy.statModifiers &&
        Object.values(itemCopy.statModifiers).some(v => v !== 0);

      // If both have no modifiers, they can stack
      if (!existingHasModifiers && !newHasModifiers) {
        return true;
      }

      // If only one has modifiers, they cannot stack
      if (existingHasModifiers !== newHasModifiers) {
        return false;
      }

      // Both have modifiers - check if they're identical
      const existingMods = existingItem.statModifiers;
      const newMods = itemCopy.statModifiers;

      // Compare all stat modifier values
      const allStats = ['strength', 'dexterity', 'intelligence', 'charisma', 'dash', 'reroll', 'skip', 'discovery', 'fov', 'luck', 'maxHealth'];
      return allStats.every(stat =>
        (existingMods[stat] || 0) === (newMods[stat] || 0)
      );
    });

    if (existingItemIndex !== -1) {
      // Item already exists with matching modifiers, increment quantity
      if (!inventory[existingItemIndex].quantity) {
        inventory[existingItemIndex].quantity = 1;
      }
      inventory[existingItemIndex].quantity++;
      targetItemIndex = existingItemIndex;
      wasStacked = true;

      // Apply item effects for the additional copy (for Passive and Triggered items)
      applyItemEffects(itemCopy);

    } else {
      // New item, add to inventory with quantity of 1
      itemCopy.quantity = 1;
      inventory.push(itemCopy);
      targetItemIndex = inventory.length - 1;


      // Apply item effects (for Passive and Triggered items) - only on first acquisition
      applyItemEffects(itemCopy);

    }
  }

  // ===== CURSE OF DECAY: Downgrade Passive Items =====
  if (itemCopy.type === 'Passive' && typeof CurseManager !== 'undefined') {
    const decayCurses = CurseManager.findByType('decay');

    if (decayCurses.length > 0 && targetItemIndex !== -1) {
      // Use the tracked index instead of searching
      let targetItem = null;
      const existingItem = inventory[targetItemIndex];

      // If the item has quantity > 1, we need to split it off for downgrading
      if (existingItem.quantity && existingItem.quantity > 1) {
        // Decrease original item quantity
        existingItem.quantity--;

        // Create a new copy with quantity 1 to downgrade
        targetItem = {
          ...existingItem,
          quantity: 1,
          statModifiers: {
            strength: 0,
            dexterity: 0,
            intelligence: 0,
            charisma: 0,
            dash: 0,
            reroll: 0,
            skip: 0,
            discovery: 0,
            fov: 0,
            luck: 0,
            maxHealth: 0,
            block: 0
          }
        };

        // Add the split item to inventory
        inventory.push(targetItem);
      } else {
        // Item has quantity 1, downgrade it directly
        targetItem = existingItem;
      }

      if (targetItem) {
        // Calculate total downgrade amount (stacking curses)
        // Each decay curse applies -1, so 2 curses = -2, 3 curses = -3, etc.
        const totalDowngrade = -1 * decayCurses.length;

        // Downgrade the item with stacked amount
        downgradePassiveItem(targetItem, totalDowngrade);
      }

      // Track decay uses for each curse instance (by unique ID)
      if (!gameState.decayUses) {
        gameState.decayUses = {};
      }

      // Process each decay curse and increment its counter
      decayCurses.forEach(curse => {
        // Use curse._id if available (for unique instances), otherwise fall back to name
        const curseKey = curse._id || curse.name;

        if (!gameState.decayUses[curseKey]) {
          gameState.decayUses[curseKey] = 0;
        }
        gameState.decayUses[curseKey]++;

        // Get max uses based on power level
        const maxUses = curse.power === 'High' ? 3 : curse.power === 'Medium' ? 2 : 1;


        // Check if curse should be removed
        if (gameState.decayUses[curseKey] >= maxUses) {
          CurseManager.consume(curse, { updateUI: true, notify: true });
          delete gameState.decayUses[curseKey];
        }
      });

      // Update curses display
      if (typeof updateCursesDisplay === 'function') {
        updateCursesDisplay();
      }
    }
  }

  gameState.inventory = [...inventory];


  // Update UI
  updateInventory();
}

// ===== HELPER FUNCTIONS =====

/**
 * Get item by name (for debugging/testing)
 * @param {string} name - Item name
 * @returns {Object|null} Item object or null
 */
function getItemByName(name) {
  return items.find(i => i.name === name) || null;
}

/**
 * Check if item has effects defined
 * @param {string} itemName - Item name
 * @returns {boolean} True if effects are defined
 */
function hasItemEffects(itemName) {
  return ITEM_EFFECTS.hasOwnProperty(itemName);
}

// ===== USABLE ITEMS SYSTEM =====

/**
 * Check if an item can be used right now
 * @param {Object} item - The item to check
 * @returns {boolean} True if the item can be used
 */
function canUseItem(item) {
  if (!item || item.type !== 'Usable') return false;

  const effects = ITEM_EFFECTS[item.name];
  if (!effects || !effects.canUse) return false;

  return effects.canUse();
}

/**
 * Use an item from inventory
 * @param {number} itemIndex - Index of item in inventory
 */
function useItem(itemIndex) {
  if (itemIndex < 0 || itemIndex >= inventory.length) {
    console.error('Invalid item index:', itemIndex);
    return;
  }

  const item = inventory[itemIndex];
  if (item.type !== 'Usable') {
    console.warn('Item is not usable:', item.name);
    return;
  }

  if (!canUseItem(item)) {
    console.warn('Cannot use item right now:', item.name);
    return;
  }

  const effects = ITEM_EFFECTS[item.name];
  if (effects && effects.onUse) {
    effects.onUse();

    // Decrement uses
    if (item.uses && item.uses > 1) {
      item.uses--;
      gameState.inventory = [...inventory];
    } else {
      // Remove item from inventory when uses reach 0 (handle quantity)
      if (item.quantity && item.quantity > 1) {
        item.quantity--;
      } else {
        inventory.splice(itemIndex, 1);
      }
      gameState.inventory = [...inventory];
    }

    // Update UI
    updateInventory();
  }
}

/**
 * Teleport to a random connected game of a specific type
 * @param {string|null} gameType - The type of game to teleport to (e.g., 'Deckbuilding', 'Action', 'Traditional', 'Strategy')
 *                                  If null or undefined, teleports to any connected game
 * @returns {boolean} - Returns true if teleport was successful, false otherwise
 */
function teleportToRandomGameOfType(gameType = null) {
  // Filter connected games, optionally by type, excluding current game
  let filteredGames;
  if (gameType) {
    filteredGames = games.filter(g =>
      g.connected === true &&
      g.type === gameType &&
      g.name !== gameState.currentGame
    );
  } else {
    filteredGames = games.filter(g =>
      g.connected === true &&
      g.name !== gameState.currentGame
    );
  }

  if (filteredGames.length === 0) {
    const errorMsg = gameType
      ? `No other connected ${gameType} games available!`
      : 'No other connected games available!';
    console.error(errorMsg);
    alert(errorMsg);
    return false;
  }

  // Pick a random game from filtered list
  const randomGame = filteredGames[Math.floor(Math.random() * filteredGames.length)];

  const teleportMsg = gameType
    ? `Teleporting to ${gameType} game: ${randomGame.name}`
    : `Teleporting to: ${randomGame.name}`;

  // Generate position
  const x = 450; // Center position
  const y = gameState.currentY + 200;

  // Advance to the selected game without triggering an encounter
  advance(randomGame.name, x, y, null);
  return true;
}

/**
 * Teleport to a random connected game (any type)
 */
function teleportToRandomGame() {
  return teleportToRandomGameOfType(null);
}

/**
 * Teleport to a random Deckbuilding game
 */
function teleportToRandomDeckbuilder() {
  return teleportToRandomGameOfType('Deckbuilding');
}

/**
 * Show a selection popup and teleport to the chosen game
 * @param {Object} options - Filter and display options
 * @param {number} options.numChoices - Number of games to show (default: 3)
 * @param {number|null} options.year - Filter by specific year (optional)
 * @param {string|null} options.type - Filter by game type (optional)
 * @param {Array<string>|null} options.tags - Filter by tags (optional, matches ANY tag)
 * @param {string} options.title - Title for the selection modal (default: "Choose Your Destination")
 * @returns {boolean} - Returns true if teleport was initiated, false otherwise
 */
function selectedTeleport(options = {}) {
  const {
    numChoices = 3,
    year = null,
    type = null,
    tags = null,
    title = "Choose Your Destination"
  } = options;

  // Start with connected games only, excluding current game
  let filteredGames = games.filter(g =>
    g.connected === true &&
    g.name !== gameState.currentGame
  );

  // Apply year filter
  if (year !== null) {
    filteredGames = filteredGames.filter(g => g.year === year);
  }

  // Apply type filter
  if (type !== null) {
    filteredGames = filteredGames.filter(g => g.type === type);
  }

  // Apply tags filter (matches if game has ANY of the specified tags)
  if (tags !== null && Array.isArray(tags) && tags.length > 0) {
    filteredGames = filteredGames.filter(g =>
      g.tags && Array.isArray(g.tags) && tags.some(tag => g.tags.includes(tag))
    );
  }

  // Check if we have enough games
  if (filteredGames.length === 0) {
    alert('No other games match your criteria!');
    return false;
  }

  // Randomly select games from filtered list
  const shuffled = [...filteredGames].sort(() => Math.random() - 0.5);
  const selectedGames = shuffled.slice(0, Math.min(numChoices, shuffled.length));

  // Build filter description for subtitle
  let filterDesc = [];
  if (year !== null) filterDesc.push(`Year: ${year}`);
  if (type !== null) filterDesc.push(`Type: ${type}`);
  if (tags !== null && tags.length > 0) filterDesc.push(`Tags: ${tags.join(', ')}`);
  const subtitle = filterDesc.length > 0 ? filterDesc.join(' • ') : 'Connected Games';

  // Create the modal HTML
  const gamesHTML = selectedGames.map(game => `
    <div class="teleport-choice" data-game-name="${game.name}" style="
      background: linear-gradient(145deg, #3a3430, #2a2420);
      border: 2px solid #cc6600;
      border-radius: 12px;
      padding: 20px;
      margin: 10px 0;
      cursor: pointer;
      transition: all 0.2s ease;
      text-align: center;
      position: relative;
    ">
      <button class="map-preview-btn" data-preview-game="${game.name.replace(/"/g, '&quot;')}"
        style="position:absolute;top:8px;left:8px;width:26px;height:26px;padding:0;background:#1a3a4a;border:1px solid #44aacc;border-radius:50%;cursor:pointer;font-size:14px;line-height:1;z-index:10;"
        title="Preview map from here to amulet">🗺</button>
      <h3 style="color: #f39c12; margin: 0 0 10px 0; font-size: 18px;">${game.name}</h3>
      <div style="display: flex; justify-content: center; gap: 15px; margin-bottom: 10px;">
        <span style="color: #888; font-size: 14px;">📅 ${game.year}</span>
        <span style="color: #4a9eff; font-size: 14px;">🎮 ${game.type}</span>
      </div>
      ${game.tags && game.tags.length > 0 ? `
        <div style="color: #999; font-size: 12px; margin-top: 8px;">
          🏷️ ${game.tags.join(', ')}
        </div>
      ` : ''}
    </div>
  `).join('');

  // Show modal using createGameModal
  if (typeof createGameModal === 'function') {
    createGameModal(`
      <div style="text-align: center;">
        <h2 style="color: #f39c12; margin-top: 0;">${title}</h2>
        <p style="color: #888; margin-bottom: 20px; font-size: 14px;">${subtitle}</p>
        <div style="max-height: 400px; overflow-y: auto;">
          ${gamesHTML}
        </div>
      </div>
    `);

    // Map preview button handlers for teleport choices
    const teleportOpts = { numChoices, year, type, tags, title };
    document.querySelectorAll('.map-preview-btn[data-preview-game]').forEach(btn => {
      btn.onclick = (e) => {
        e.stopPropagation();
        if (typeof showGameMapPreview === 'function') {
          showGameMapPreview(btn.dataset.previewGame, () => selectedTeleport(teleportOpts));
        }
      };
    });

    // Add click handlers to teleport choices
    document.querySelectorAll('.teleport-choice').forEach(choice => {
      choice.onmouseenter = () => {
        choice.style.background = 'linear-gradient(145deg, #cc6600, #aa5500)';
        choice.style.borderColor = '#ff8800';
        choice.style.transform = 'translateY(-2px)';
        choice.style.boxShadow = '0 4px 12px rgba(204, 102, 0, 0.4)';
      };
      choice.onmouseleave = () => {
        choice.style.background = 'linear-gradient(145deg, #3a3430, #2a2420)';
        choice.style.borderColor = '#cc6600';
        choice.style.transform = '';
        choice.style.boxShadow = '';
      };
      choice.onclick = () => {
        const gameName = choice.dataset.gameName;

        // Close modal
        if (typeof closeGameModal === 'function') {
          closeGameModal();
        }

        // Teleport to selected game without triggering an encounter
        const selectedGame = games.find(g => g.name === gameName);
        if (selectedGame) {
          const x = 450;
          const y = gameState.currentY + 200;

          advance(selectedGame.name, x, y, null);
        }
      };
    });
  } else {
    console.error('createGameModal function not found!');
    return false;
  }

  return true;
}

/**
 * Trigger onEnemyDefeated effects for all items in inventory that have this trigger
 * Call this function when the player successfully defeats an enemy
 */
function triggerOnEnemyDefeated() {
  if (!inventory || inventory.length === 0) {
    return;
  }


  // Check each item in inventory for onEnemyDefeated trigger
  inventory.forEach(item => {
    if (!item || !item.name) return;

    const itemEffects = ITEM_EFFECTS[item.name];
    if (itemEffects && typeof itemEffects.onEnemyDefeated === 'function') {
      itemEffects.onEnemyDefeated();
    }
  });
}

/**
 * Trigger onCombatEnd effects for all items in inventory that have this trigger
 * Call this function when the player wins a combat encounter
 */
function triggerOnCombatEnd(combatState) {
  if (!inventory || inventory.length === 0) {
    return;
  }


  // Track which item names have already been processed to avoid double-triggering
  // when stacking is handled inside the effect itself
  const processed = new Set();

  inventory.forEach(item => {
    if (!item || !item.name) return;
    if (processed.has(item.name)) return;

    const itemEffects = ITEM_EFFECTS[item.name];
    if (itemEffects && typeof itemEffects.onCombatEnd === 'function') {
      itemEffects.onCombatEnd(combatState);
      processed.add(item.name);
    }
  });
}

/**
 * Trigger onCurseAdded effects for all items in inventory that have this trigger
 * Call this function when the player obtains a new curse
 */
function triggerOnCurseAdded() {
  if (!inventory || inventory.length === 0) {
    return;
  }


  // Check each item in inventory for onCurseAdded trigger
  inventory.forEach(item => {
    if (!item || !item.name) return;

    const itemEffects = ITEM_EFFECTS[item.name];
    if (itemEffects && typeof itemEffects.onCurseAdded === 'function') {
      itemEffects.onCurseAdded();
    }
  });
}

/**
 * Trigger onCurseRemoved effects for all items in inventory that have this trigger
 * Call this function when the player removes a curse
 */
function triggerOnCurseRemoved() {
  if (!inventory || inventory.length === 0) {
    return;
  }


  // Check each item in inventory for onCurseRemoved trigger
  inventory.forEach(item => {
    if (!item || !item.name) return;

    const itemEffects = ITEM_EFFECTS[item.name];
    if (itemEffects && typeof itemEffects.onCurseRemoved === 'function') {
      itemEffects.onCurseRemoved();
    }
  });
}

/**
 * Trigger onGameBeaten effects for all items in inventory that have this trigger
 * Call this function when the player successfully beats a game
 */
function triggerOnGameBeaten() {
  if (!inventory || inventory.length === 0) {
    return;
  }


  // Check each item in inventory for onGameBeaten trigger
  // Use a copy of inventory array since items might be removed during iteration
  [...inventory].forEach(item => {
    if (!item || !item.name) return;

    const itemEffects = ITEM_EFFECTS[item.name];
    if (itemEffects && typeof itemEffects.onGameBeaten === 'function') {
      itemEffects.onGameBeaten();
    }
  });
}

/**
 * Show Wand of Wishing item selection UI
 * Displays all unlocked items in a collection-style grid with hover tooltips
 */
function showWandOfWishingSelection() {
  if (!items || items.length === 0) {
    alert('No items available!');
    return;
  }

  // Filter for unlocked items only (defaults to true if not specified)
  // Also exclude the Wand of Wishing itself
  const unlockedItems = items.filter(item => item.unlocked !== false && item.name !== 'Wand of Wishing');

  // Sort items by rarity then alphabetically
  const rarityOrder = { 'legendary': 4, 'rare': 3, 'uncommon': 2, 'common': 1 };
  const sortedItems = [...unlockedItems].sort((a, b) => {
    const rarityDiff = (rarityOrder[b.rarity] || 0) - (rarityOrder[a.rarity] || 0);
    if (rarityDiff !== 0) return rarityDiff;
    return a.name.localeCompare(b.name);
  });

  // Get rarity color
  const getRarityColor = (rarity) => {
    switch(rarity) {
      case 'legendary': return '#ff6b00'; // Orange/gold
      case 'rare': return '#9b59b6';      // Purple
      case 'uncommon': return '#4CAF50';  // Green
      case 'common': return '#aaa';       // Gray
      default: return '#888';
    }
  };

  // Create items grid HTML
  const itemsHTML = sortedItems.map(item => `
    <div class="wand-item-card" data-item-name="${item.name.replace(/"/g, '&quot;')}" style="
      background: rgba(0,0,0,0.3);
      border: 2px solid ${getRarityColor(item.rarity)};
      border-radius: 8px;
      padding: 12px;
      display: flex;
      flex-direction: column;
      gap: 8px;
      transition: all 0.2s;
      cursor: pointer;
      position: relative;
    ">
      <img
        src="${item.image || 'images/items/no-item.svg'}"
        alt="${item.name}"
        style="
          width: 100%;
          height: 96px;
          object-fit: contain;
          border-radius: 6px;
          background: rgba(0,0,0,0.2);
          image-rendering: pixelated;
        "
        onerror="this.style.display='none';"
      />
      <div style="text-align: center; font-size: 13px; font-weight: bold; color: ${getRarityColor(item.rarity)}; word-wrap: break-word;">
        ${item.name}
      </div>
      <div style="font-size: 10px; color: ${getRarityColor(item.rarity)}; text-align: center; text-transform: uppercase; font-weight: bold;">
        ${item.rarity}
      </div>
      <div class="item-tooltip" style="display: none; position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%); background: #2a2420; color: #e6d5b8; padding: 15px; border: 2px solid ${getRarityColor(item.rarity)}; border-radius: 8px; font-size: 13px; z-index: 100000; min-width: 300px; max-width: 400px; white-space: normal; box-shadow: 0 8px 24px rgba(0,0,0,0.7); pointer-events: none;">
        <div style="font-weight: bold; margin-bottom: 8px; color: ${getRarityColor(item.rarity)}; font-size: 15px;">${item.name}</div>
        <div style="color: #888; font-size: 11px; margin-bottom: 10px;">${item.type} • ${item.reference || 'Unknown'}</div>
        <div style="line-height: 1.6;">${item.description || 'No description'}</div>
        ${item.tags && item.tags.length > 0 ? `<div style="margin-top: 8px; padding-top: 8px; border-top: 1px solid rgba(255,255,255,0.2); font-size: 10px; color: #aaa;">Tags: ${item.tags.join(', ')}</div>` : ''}
      </div>
    </div>
  `).join('');

  // Show modal
  if (typeof createGameModal === 'function') {
    createGameModal(`
      <div style="width: 90vw; max-width: 1200px; max-height: 85vh; overflow: hidden; display: flex; flex-direction: column;">
        <h2 style="color: #ff6b00; margin: 0 0 15px 0; text-align: center;">✨ Wand of Wishing ✨</h2>
        <p style="color: #aaa; text-align: center; margin-bottom: 20px; font-size: 14px;">
          Choose any item to add to your inventory
        </p>
        <div style="flex: 1; overflow-y: auto; padding: 10px;">
          <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 15px;">
            ${itemsHTML}
          </div>
        </div>
        <div style="text-align: center; margin-top: 15px; padding-top: 15px; border-top: 2px solid #444;">
          <button onclick="closeGameModal();" style="padding: 10px 30px; background: #444; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold;">Cancel</button>
        </div>
      </div>
    `);

    // Add hover and click handlers
    document.querySelectorAll('.wand-item-card').forEach(card => {
      const tooltip = card.querySelector('.item-tooltip');

      card.onmouseenter = (e) => {
        e.currentTarget.style.transform = 'translateY(-5px) scale(1.05)';
        e.currentTarget.style.boxShadow = '0 10px 30px rgba(255, 107, 0, 0.4)';
        if (tooltip) tooltip.style.display = 'block';
      };

      card.onmouseleave = (e) => {
        e.currentTarget.style.transform = '';
        e.currentTarget.style.boxShadow = '';
        if (tooltip) tooltip.style.display = 'none';
      };

      card.onclick = (e) => {
        const itemName = e.currentTarget.dataset.itemName;
        const selectedItem = items.find(i => i.name === itemName);

        if (selectedItem) {

          // Acquire the item
          acquireItem(selectedItem);

          // Close modal
          if (typeof closeGameModal === 'function') {
            closeGameModal();
          }

          // Show notification
          setTimeout(() => {
            createNotification(`Wished for ${itemName}!`, 'rgba(255, 107, 0, 0.95)', '✨');
          }, 100);
        }
      };
    });
  } else {
    console.error('createGameModal function not found!');
  }
}

/**
 * Show Poop item game selection UI
 * Displays all visible connected games for applying stinky status
 */
function showPoopSelection() {
  const currentGame = gameState.currentGame;
  if (!currentGame) {
    alert('No current game!');
    return;
  }

  // Get all connected games (visible on map)
  const connectedGames = typeof getGameConnections === 'function'
    ? getGameConnections(currentGame)
    : [];

  if (connectedGames.length === 0) {
    alert('No connected games available!');
    return;
  }

  // Filter out games that already have stinky status
  const availableGames = connectedGames.filter(gameName =>
    typeof hasGameStatus !== 'function' || !hasGameStatus(gameName, 'stinky')
  );

  if (availableGames.length === 0) {
    alert('All connected games are already stinky!');
    return;
  }

  // Get game type for color coding
  const getGameTypeColor = (gameName) => {
    const game = games?.find(g => g.name === gameName);
    if (!game || !game.type) return '#888';

    switch(game.type.toLowerCase()) {
      case 'action': return '#ff4444';
      case 'deckbuilding': return '#bb66ff';
      case 'strategy': return '#4488ff';
      case 'traditional': return '#44ff44';
      default: return '#888';
    }
  };

  // Create games grid HTML
  const gamesHTML = availableGames.map(gameName => {
    const game = games?.find(g => g.name === gameName);
    const typeColor = getGameTypeColor(gameName);

    return `
      <div class="poop-game-card" data-game-name="${gameName.replace(/"/g, '&quot;')}" style="
        background: rgba(0,0,0,0.3);
        border: 2px solid ${typeColor};
        border-radius: 8px;
        padding: 12px;
        display: flex;
        flex-direction: column;
        gap: 8px;
        cursor: pointer;
        transition: all 0.2s;
        position: relative;
      ">
        <button class="poop-preview-btn" data-preview-game="${gameName.replace(/"/g, '&quot;')}"
          style="position:absolute;top:5px;left:5px;width:22px;height:22px;padding:0;background:#1a3a4a;border:1px solid #44aacc;border-radius:50%;cursor:pointer;font-size:11px;line-height:1;z-index:10;"
          title="Preview map from here to amulet">🗺</button>
        <div style="font-weight: bold; color: white; text-align: center; font-size: 14px;">
          ${gameName}
        </div>
        <div style="color: #aaa; text-align: center; font-size: 12px;">
          ${game?.type || 'Unknown'}
        </div>
      </div>
    `;
  }).join('');

  // Create modal
  if (typeof createGameModal === 'function') {
    createGameModal(`
      <div style="
        background: rgba(20,20,20,0.98);
        padding: 30px;
        border-radius: 12px;
        border: 3px solid #8B4513;
        max-width: 600px;
        max-height: 80vh;
        display: flex;
        flex-direction: column;
      ">
        <h2 style="color: #8B4513; margin: 0 0 15px 0; text-align: center;">💩 The Poop 💩</h2>
        <p style="color: #aaa; text-align: center; margin-bottom: 20px; font-size: 14px;">
          Choose a game to make STINKY!<br>
          <span style="font-size: 12px; color: #888;">Stinky games are deprioritized in selections</span>
        </p>
        <div style="flex: 1; overflow-y: auto; padding: 10px;">
          <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 15px;">
            ${gamesHTML}
          </div>
        </div>
        <div style="text-align: center; margin-top: 15px; padding-top: 15px; border-top: 2px solid #444;">
          <button onclick="closeGameModal();" style="padding: 10px 30px; background: #444; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold;">Cancel</button>
        </div>
      </div>
    `);

    // Map preview button handlers for poop selection
    document.querySelectorAll('.poop-preview-btn[data-preview-game]').forEach(btn => {
      btn.onclick = (e) => {
        e.stopPropagation();
        if (typeof showGameMapPreview === 'function') {
          showGameMapPreview(btn.dataset.previewGame, () => showPoopSelection());
        }
      };
    });

    // Add hover and click handlers
    document.querySelectorAll('.poop-game-card').forEach(card => {
      card.onmouseenter = (e) => {
        e.currentTarget.style.transform = 'translateY(-5px) scale(1.05)';
        e.currentTarget.style.boxShadow = '0 10px 30px rgba(139, 69, 19, 0.4)';
      };

      card.onmouseleave = (e) => {
        e.currentTarget.style.transform = '';
        e.currentTarget.style.boxShadow = '';
      };

      card.onclick = (e) => {
        const selectedGameName = e.currentTarget.dataset.gameName;

        if (selectedGameName) {

          // Apply stinky status
          if (typeof addGameStatus === 'function') {
            addGameStatus(selectedGameName, 'stinky', '💩');
          }

          // Close modal
          if (typeof closeGameModal === 'function') {
            closeGameModal();
          }

          // Show notification
          setTimeout(() => {
            createNotification(`${selectedGameName} is now STINKY!`, 'rgba(139, 69, 19, 0.95)', '💩');
          }, 100);
        }
      };
    });
  } else {
    console.error('createGameModal function not found!');
  }
}

// ===== PASSIVE ITEM STAT MODIFIERS =====

/**
 * Initialize stat modifiers on a passive item
 * @param {Object} item - The passive item
 */
function initializePassiveModifiers(item) {
  if (!item.statModifiers) {
    item.statModifiers = {
      strength: 0,
      dexterity: 0,
      intelligence: 0,
      charisma: 0,
      dash: 0,
      reroll: 0,
      skip: 0,
      discovery: 0,
      fov: 0,
      luck: 0,
      maxHealth: 0,
      maxEnergy: 0,  // For items like Busted Crown, Philosopher's Stone
      block: 0  // For items like Calipers that grant block in combat
    };
  }
  // Ensure block and maxEnergy modifiers exist on older items
  if (item.statModifiers && !('block' in item.statModifiers)) {
    item.statModifiers.block = 0;
  }
  if (item.statModifiers && !('maxEnergy' in item.statModifiers)) {
    item.statModifiers.maxEnergy = 0;
  }
}

/**
 * Get the display name for a passive item with stat modifiers
 * @param {Object} item - The passive item
 * @returns {string} Display name with modifiers (e.g., "Wheat +1" or "Lunch -2")
 */
function getPassiveDisplayName(item) {
  if (item.type !== 'Passive' || !item.statModifiers) {
    return item.name;
  }

  // Calculate total modifier value (sum of all stat changes)
  const totalModifier = Object.values(item.statModifiers).reduce((sum, val) => sum + val, 0);

  if (totalModifier === 0) {
    return item.name;
  }

  const modifierText = totalModifier > 0 ? `+${totalModifier}` : `${totalModifier}`;
  return `${item.name} ${modifierText}`;
}

/**
 * Get the modifier description text for a passive item
 * @param {Object} item - The passive item
 * @returns {string} Description of all active stat modifiers
 */
function getPassiveModifierDescription(item) {
  if (item.type !== 'Passive' || !item.statModifiers) {
    return '';
  }

  const modifiers = [];
  const statNames = {
    strength: 'Strength',
    dexterity: 'Dexterity',
    intelligence: 'Intelligence',
    charisma: 'Charisma',
    dash: 'Dash',
    reroll: 'Reroll',
    skip: 'Skip',
    discovery: 'Discovery',
    fov: 'Field of View',
    luck: 'Luck',
    maxHealth: 'Max Health'
  };

  for (const [stat, value] of Object.entries(item.statModifiers)) {
    if (value !== 0) {
      const sign = value > 0 ? '+' : '';
      modifiers.push(`${sign}${value} ${statNames[stat]}`);
    }
  }

  return modifiers.length > 0 ? modifiers.join(', ') : '';
}

/**
 * Upgrade or downgrade a random passive item
 * @param {boolean} isUpgrade - True to upgrade, false to downgrade
 * @returns {Object|null} Result object with success, itemName, and isUpgrade
 */
function upgradeOrDowngradePassive(isUpgrade) {
  // Get all passive items in inventory
  const passiveItems = inventory.filter(item => item.type === 'Passive');

  if (passiveItems.length === 0) {
    return { success: false };
  }

  // Select random passive item
  const randomItem = passiveItems[Math.floor(Math.random() * passiveItems.length)];

  // If item has quantity > 1, we need to split it
  let itemToModify = randomItem;
  if (randomItem.quantity && randomItem.quantity > 1) {
    // Decrease original item quantity
    randomItem.quantity--;

    // Create a new copy with quantity 1
    itemToModify = {
      ...randomItem,
      quantity: 1,
      statModifiers: {
        strength: 0,
        dexterity: 0,
        intelligence: 0,
        charisma: 0,
        dash: 0,
        reroll: 0,
        skip: 0,
        discovery: 0,
        fov: 0,
        luck: 0,
        maxHealth: 0,
        block: 0
      }
    };

    // Add the split item to inventory
    inventory.push(itemToModify);
  }

  // Initialize modifiers if not present
  initializePassiveModifiers(itemToModify);

  // Get all stat modifications this item provides
  const statModifications = getItemStatModifications(itemToModify.name);

  // If no stat modifications found, fall back to random stat (shouldn't happen for items with effects)
  if (statModifications.length === 0) {
    console.warn(`No stat modifications found for ${itemToModify.name}, using fallback`);
    const availableStats = ['strength', 'dexterity', 'intelligence', 'charisma', 'dash', 'reroll', 'skip', 'discovery', 'fov', 'luck', 'maxHealth', 'maxEnergy', 'block'];
    const randomStat = availableStats[Math.floor(Math.random() * availableStats.length)];
    statModifications.push({ stat: randomStat, direction: 1 });
  }

  // Store the original name if not already stored
  if (!itemToModify.originalName) {
    itemToModify.originalName = itemToModify.name;
  }

  // Store the original description if not already stored
  if (!itemToModify.originalDescription) {
    itemToModify.originalDescription = itemToModify.description;
  }

  // Apply upgrade/downgrade to ALL stats this item provides
  const modifiedStats = [];
  const baseChange = isUpgrade ? 1 : -1;

  statModifications.forEach(({ stat }) => {
    // Apply the same change amount to each stat uniformly
    // E.g., if item gives +2 strength, upgrade by +1 makes it +3 strength
    // If item gives -2 strength, upgrade by +1 makes it -1 strength (less penalty)
    const change = baseChange;

    itemToModify.statModifiers[stat] += change;

    // Apply the stat change to the game state
    if (stat === 'maxHealth') {
      // Handle max health specially
      if (typeof StateMutator !== 'undefined' && typeof StateMutator.modifyMaxHealth === 'function') {
        StateMutator.modifyMaxHealth(change);
      } else {
        maxHealth += change;
        gameState.maxHealth = maxHealth;
        health = Math.min(health, maxHealth);
        gameState.health = health;
      }
    } else if (stat === 'maxEnergy') {
      // Handle max energy
      if (typeof StateMutator !== 'undefined' && typeof StateMutator.modifyMaxEnergy === 'function') {
        StateMutator.modifyMaxEnergy(change);
      } else {
        gameState.maxEnergy = (gameState.maxEnergy || 2) + change;
      }
    } else if (stat === 'discovery') {
      // Handle discovery
      if (typeof StateMutator !== 'undefined' && typeof StateMutator.modifyDiscovery === 'function') {
        StateMutator.modifyDiscovery(change);
      } else {
        discovery += change;
        gameState.discovery = discovery;
      }
    } else {
      updateStat(stat, change);
    }

    modifiedStats.push({ stat, change });
  });

  // Update the display name
  itemToModify.displayName = getPassiveDisplayName(itemToModify);

  // Update the description with modifier info
  const modifierDesc = getPassiveModifierDescription(itemToModify);
  if (modifierDesc) {
    itemToModify.description = `${itemToModify.originalDescription}\n\n[Modified: ${modifierDesc}]`;
  }

  // Update gameState
  gameState.inventory = [...inventory];

  // Update UI
  if (typeof updateInventory === 'function') {
    updateInventory();
  }

  // Show notification for all modified stats
  if (typeof createNotification === 'function') {
    const statsText = modifiedStats.map(({ stat, change }) => {
      const statDisplay = stat === 'maxHealth' ? 'Max Health' : stat.charAt(0).toUpperCase() + stat.slice(1);
      return `${statDisplay} ${change > 0 ? '+' : ''}${change}`;
    }).join(', ');
    const emoji = isUpgrade ? '⬆️' : '⬇️';
    const color = isUpgrade ? '#66bb6a' : '#ff8a65';
    createNotification(`${emoji} ${itemToModify.originalName || itemToModify.name} - ${statsText}`, color, emoji);
  }

  return {
    success: true,
    itemName: itemToModify.displayName || itemToModify.name,
    isUpgrade: isUpgrade,
    stats: modifiedStats,
    change: baseChange
  };
}

/**
 * Remove all stat effects from an item when it's removed from inventory
 * @param {Object} item - The item being removed
 */
function removeItemStatEffects(item) {
  if (item.type !== 'Passive' || !item.statModifiers) {
    return;
  }

  // Reverse all stat modifiers
  Object.entries(item.statModifiers).forEach(([stat, value]) => {
    if (value !== 0) {
      updateStat(stat, -value);
    }
  });
}

// Export functions to global scope
window.createNotification = createNotification;
window.applyItemEffects = applyItemEffects;
window.acquireItem = acquireItem;
window.getItemByName = getItemByName;
window.hasItemEffects = hasItemEffects;
window.canUseItem = canUseItem;
window.useItem = useItem;
window.teleportToRandomGameOfType = teleportToRandomGameOfType; // Random teleport by type
window.selectedTeleport = selectedTeleport; // Selected teleport with filters
window.teleportToRandomGame = teleportToRandomGame;
window.teleportToRandomDeckbuilder = teleportToRandomDeckbuilder;
window.triggerOnEnemyDefeated = triggerOnEnemyDefeated; // Trigger onEnemyDefeated effects
window.triggerOnCombatEnd = triggerOnCombatEnd; // Trigger onCombatEnd effects
window.triggerOnCurseAdded = triggerOnCurseAdded; // Trigger onCurseAdded effects
window.triggerOnCurseRemoved = triggerOnCurseRemoved; // Trigger onCurseRemoved effects
window.triggerOnGameBeaten = triggerOnGameBeaten; // Trigger onGameBeaten effects
window.showWandOfWishingSelection = showWandOfWishingSelection; // Wand of Wishing UI
window.showPoopSelection = showPoopSelection; // Poop selection UI
window.calculateDamageReduction = calculateDamageReduction; // Damage reduction from items
window.ITEM_EFFECTS = ITEM_EFFECTS;
window.initializePassiveModifiers = initializePassiveModifiers; // Initialize stat modifiers
window.getPassiveDisplayName = getPassiveDisplayName; // Get display name with modifiers
window.getPassiveModifierDescription = getPassiveModifierDescription; // Get modifier description text
window.upgradeOrDowngradePassive = upgradeOrDowngradePassive; // Upgrade/downgrade passive
window.downgradeRandomPassiveItem = () => upgradeOrDowngradePassive(false); // Rust hook
window.removeItemStatEffects = removeItemStatEffects; // Remove stat effects when item removed
