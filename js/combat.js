// ===== COMBAT.JS - Combat System, Dice Rolling, Stat Checks =====
//
// This module handles:
// - Enemy generation and selection
// - D20 dice rolling
// - Combat outcomes (success/failure)
// - Stat checks and modifiers
// - Rewards and consequences

// ===== HELPER FUNCTIONS =====

// Calculate damage based on curse power level
function getCurseDamage(power) {
  if (power === 'High') return 4;
  if (power === 'Medium') return 3;
  return 2; // Low
}

// Update both curse display systems
function updateCurseDisplays() {
  if (typeof updateCursesDisplay === 'function') {
    updateCursesDisplay();
  }
  if (typeof updateActiveCursesList === 'function') {
    updateActiveCursesList();
  }
}

// ===== COMBAT OUTCOME APPLICATION =====

function applyCombatOutcome(success) {
  if (!currentEnemy) return;

  let outcomeText;
  if (success) {
    // Parse and apply success rewards
    const goldMatch = currentEnemy.successReward.match(/(\d+) gold/i);
    if (goldMatch) {
      const goldAmount = parseInt(goldMatch[1]);
      gold += goldAmount;
      updateTopBar();
    }

    // Check for item rewards
    if (currentEnemy.successReward.toLowerCase().includes('item')) {
      if (currentEnemy.successReward.toLowerCase().includes('common')) {
        giveRandomItem('common');
      } else if (currentEnemy.successReward.toLowerCase().includes('uncommon')) {
        giveRandomItem('uncommon');
      } else if (currentEnemy.successReward.toLowerCase().includes('rare')) {
        giveRandomItem('rare');
      }
    }

    outcomeText = `Defeated ${currentEnemy.name}: ${currentEnemy.successReward}`;
  } else {
    // Parse and apply failure consequences
    const failureText = document.getElementById('failureOutcome').textContent;
    console.log('Combat failure - parsing text:', failureText);

    const healthMatch = failureText.match(/(\d+) health/i);
    if (healthMatch) {
      const healthLoss = parseInt(healthMatch[1]);
      const oldHealth = health;
      health = Math.max(0, health - healthLoss);
      gameState.health = health;
      console.log(`Health loss: ${healthLoss}, Old health: ${oldHealth}, New health: ${health}`);
      updateHealthDisplay();
    } else {
      console.warn('No health loss found in failure text:', failureText);
    }

    const goldMatch = failureText.match(/lose (\d+) gold/i);
    if (goldMatch) {
      const goldLoss = parseInt(goldMatch[1]);
      gold = Math.max(0, gold - goldLoss);
      updateTopBar();
    }

    outcomeText = `Failed against ${currentEnemy.name}: ${failureText}`;
  }

  // Record in encounter history
  encounterHistory.push({
    type: 'combat',
    enemy: currentEnemy.name,
    outcome: outcomeText,
    roll: currentRoll,
    success: success,
    timestamp: new Date().toLocaleString()
  });

  updateEncounterHistory();
  document.getElementById('enemyDisplay').style.display = 'none';

  // Save game state after combat
  if (typeof saveCurrentGame === 'function') {
    saveCurrentGame();
  }

  if (health <= 0) {
    // Clear items and curses immediately on death
    inventory = [];
    if (gameState.activeCurses) {
      gameState.activeCurses = [];
    }

    // Show death screen with options
    setTimeout(() => {
      createGameModal(`
        <div style="text-align: center;">
          <h1 style="color: #ff4444; font-size: 48px; margin: 20px 0;">💀 YOU ARE DEAD</h1>
          <p style="color: #aaa; font-size: 18px; margin: 20px 0;">Your journey has come to an end...</p>
          <div style="margin-top: 30px; display: flex; gap: 15px; justify-content: center;">
            <button id="death-home-btn" style="
              padding: 15px 30px;
              font-size: 18px;
              background: linear-gradient(145deg, #666, #444);
              border: 2px solid #888;
              border-radius: 8px;
              color: white;
              cursor: pointer;
              font-weight: bold;
            ">🏠 Home</button>
            <button id="death-retry-btn" style="
              padding: 15px 30px;
              font-size: 18px;
              background: linear-gradient(145deg, #4CAF50, #2E7D32);
              border: 2px solid #66BB6A;
              border-radius: 8px;
              color: white;
              cursor: pointer;
              font-weight: bold;
            ">🔄 Try Again</button>
          </div>
        </div>
      `);

      // Add event listeners
      document.getElementById('death-home-btn').onclick = () => {
        closeGameModal();
        document.getElementById('dungeon-screen').style.display = 'none';
        document.getElementById('main-menu').style.display = 'flex';
      };

      document.getElementById('death-retry-btn').onclick = () => {
        // Clear UI immediately to prevent flash
        inventory = [];
        if (gameState.activeCurses) {
          gameState.activeCurses = [];
        }
        updateInventory?.();
        updateCursesDisplay?.();
        updateActiveCursesList?.();

        closeGameModal();
        document.getElementById('dungeon-screen').style.display = 'none';
        document.getElementById('main-menu').style.display = 'flex';
        // Trigger new game button click
        setTimeout(() => {
          document.getElementById('new-game-btn')?.click();
        }, 100);
      };
    }, 300);
  }
}

// ===== DICE ROLLING =====

function rollD20() {
  if (currentEnemy) {
    currentRoll = Math.floor(Math.random() * 20) + 1;
    let cursePenalty = 0;
    let curseMessages = [];

    // Check for Curse of Weakness (subtract from roll) - handle stacking
    const weaknessCurse = CurseManager.findFirstByType('weakness');
    if (weaknessCurse) {
      const penalty = CurseManager.getPenalty(weaknessCurse.power);
      cursePenalty = penalty;
      curseMessages.push(`Curse of Weakness: -${penalty}`);

      // Remove this specific curse instance after this roll
      CurseManager.consume(weaknessCurse);
    }

    // Check for Curse of Failure (damage on rolling 1) - handle stacking
    if (currentRoll === 1) {
      const failureCurses = CurseManager.findByType('failure');
      if (failureCurses.length > 0) {
        // Trigger all failure curses - sum total damage
        const totalDamage = failureCurses.reduce((sum, curse) => sum + CurseManager.getPenalty(curse.power), 0);

        StateMutator.modifyHealth(-totalDamage);

        curseMessages.push(`Curse of Failure (×${failureCurses.length}): -${totalDamage} HP!`);

        // Show popup notification for Curse of Failure damage
        setTimeout(() => {
          if (typeof createGameModal === 'function') {
            createGameModal(`
              <div style="text-align: center;">
                <h2 style="color: #ff4444; margin-top: 0; font-size: 32px;">😱 Curse of Failure!</h2>
                <p style="font-size: 18px; color: #ff8888;">You rolled a natural 1!</p>
                <p style="font-size: 20px; font-weight: bold; color: #ff0000; margin: 15px 0;">
                  ⚠️ CRITICAL FAILURE - Combat Auto-Lost!
                </p>
                <p style="font-size: 24px; font-weight: bold; color: #ff6666; margin: 20px 0;">
                  -${totalDamage} HP
                </p>
                ${failureCurses.length > 1 ? `<p style="color: #cc8888; font-size: 14px;">${failureCurses.length} curses triggered</p>` : ''}
                <button onclick="closeGameModal()" style="
                  padding: 10px 30px;
                  margin-top: 20px;
                  background: #ff4444;
                  border: none;
                  border-radius: 6px;
                  color: white;
                  cursor: pointer;
                  font-weight: bold;
                ">Continue</button>
              </div>
            `);
          }
        }, 500);

        // Remove all failure curses after triggering
        gameState.activeCurses = gameState.activeCurses.filter(c => !c.name.toLowerCase().includes('failure'));
        updateCurseDisplays();

        // Check for death
        if (health <= 0 && typeof handleDeath === 'function') {
          setTimeout(() => handleDeath(), 500);
        }
      }
    }

    // Apply stat modifiers
    const stat = currentEnemy.stat;
    const modifier = getStatModifier(stat);
    const totalRoll = currentRoll + modifier - cursePenalty;
    const check = currentEnemy.rollCheck;

    // Curse of Failure causes critical fail - auto-lose combat
    const criticalFail = currentRoll === 1 && gameState?.activeCurses?.some(c => c.name.toLowerCase().includes('failure'));
    const success = criticalFail ? false : (totalRoll >= check);

    let resultText = `Rolled: ${currentRoll}`;
    if (modifier !== 0) {
      resultText += ` + ${modifier} (${stat})`;
    }
    if (cursePenalty > 0) {
      resultText += ` - ${cursePenalty} (Weakness)`;
    }
    if (cursePenalty > 0 || modifier !== 0) {
      resultText += ` = ${totalRoll}`;
    }
    resultText += ` vs DC ${check}`;

    if (criticalFail) {
      resultText += ' ✗ CRITICAL FAILURE';
      document.getElementById('rollResult').style.color = '#ff0000';
    } else if (success) {
      resultText += ' ✓ SUCCESS';
      document.getElementById('rollResult').style.color = '#4CAF50';
    } else {
      resultText += ' ✗ FAILURE';
      document.getElementById('rollResult').style.color = '#ff4444';
    }

    // Add curse messages
    if (curseMessages.length > 0) {
      resultText += '\n' + curseMessages.join(', ');
    }

    document.getElementById('rollResult').textContent = resultText;
    return success;
  }
  return false;
}

// ===== HELPER FUNCTIONS =====

function giveRandomItem(rarity) {
  const rarityItems = items.filter(item => item.rarity === rarity);
  if (rarityItems.length > 0) {
    const randomIndex = Math.floor(Math.random() * rarityItems.length);
    const item = rarityItems[randomIndex];
    acquireItem(item);
  }
}

function getStatModifier(statName) {
  switch(statName.toLowerCase()) {
    case 'strength': return strength;
    case 'dexterity': return dexterity;
    case 'intelligence': return intelligence;
    case 'charisma': return charisma;
    default: return 0;
  }
}

function applyStatBonus(statName, amount) {
  switch(statName.toLowerCase()) {
    case 'strength':
      strength += amount;
      break;
    case 'dexterity':
      dexterity += amount;
      break;
    case 'intelligence':
      intelligence += amount;
      break;
    case 'charisma':
      charisma += amount;
      break;
  }
  updateGameStats();
}

// Export to global scope
window.applyCombatOutcome = applyCombatOutcome;
window.rollD20 = rollD20;
window.giveRandomItem = giveRandomItem;
window.getStatModifier = getStatModifier;
window.applyStatBonus = applyStatBonus;
