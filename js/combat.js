// ===== COMBAT.JS - Combat System, Dice Rolling, Stat Checks =====
//
// This module handles:
// - Enemy generation and selection
// - D20 dice rolling
// - Combat outcomes (success/failure)
// - Stat checks and modifiers
// - Rewards and consequences

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
    if (gameState && gameState.activeCurses) {
      const weaknessCurses = gameState.activeCurses.filter(c => c.name.toLowerCase().includes('weakness'));
      if (weaknessCurses.length > 0) {
        // Use only the first weakness curse and remove it
        const weaknessCurse = weaknessCurses[0];
        let penalty = 0;
        if (weaknessCurse.power === 'Low') penalty = 2;
        else if (weaknessCurse.power === 'Medium') penalty = 3;
        else if (weaknessCurse.power === 'High') penalty = 4;

        cursePenalty = penalty;
        curseMessages.push(`Curse of Weakness: -${penalty}`);

        // Remove this specific curse instance after this roll
        const curseIndex = gameState.activeCurses.indexOf(weaknessCurse);
        gameState.activeCurses.splice(curseIndex, 1);

        if (typeof updateCursesDisplay === 'function') {
          updateCursesDisplay();
        }
        if (typeof updateActiveCursesList === 'function') {
          updateActiveCursesList();
        }
      }
    }

    // Check for Curse of Failure (damage on rolling 1) - handle stacking
    if (currentRoll === 1 && gameState && gameState.activeCurses) {
      const failureCurses = gameState.activeCurses.filter(c => c.name.toLowerCase().includes('failure'));
      if (failureCurses.length > 0) {
        // Trigger all failure curses if rolled a 1
        let totalDamage = 0;
        failureCurses.forEach(failureCurse => {
          let damage = 0;
          if (failureCurse.power === 'Low') damage = 2;
          else if (failureCurse.power === 'Medium') damage = 3;
          else if (failureCurse.power === 'High') damage = 4;
          totalDamage += damage;
        });

        health = Math.max(0, health - totalDamage);
        gameState.health = health;
        if (typeof updateTopBar === 'function') {
          updateTopBar();
        }

        curseMessages.push(`Curse of Failure (×${failureCurses.length}): -${totalDamage} HP!`);

        // Show popup notification for Curse of Failure damage
        setTimeout(() => {
          if (typeof createGameModal === 'function') {
            createGameModal(`
              <div style="text-align: center;">
                <h2 style="color: #ff4444; margin-top: 0; font-size: 32px;">😱 Curse of Failure!</h2>
                <p style="font-size: 18px; color: #ff8888;">You rolled a natural 1!</p>
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
        if (typeof updateCursesDisplay === 'function') {
          updateCursesDisplay();
        }
        if (typeof updateActiveCursesList === 'function') {
          updateActiveCursesList();
        }

        // Check for death
        if (health <= 0 && typeof handleDeath === 'function') {
          setTimeout(() => handleDeath(), 500);
        }
      }
    }

    // Apply stat modifiers
    let modifier = 0;
    const stat = currentEnemy.stat;

    switch(stat) {
      case 'Strength': modifier = strength; break;
      case 'Dexterity': modifier = dexterity; break;
      case 'Intelligence': modifier = intelligence; break;
      case 'Charisma': modifier = charisma; break;
    }

    const totalRoll = currentRoll + modifier - cursePenalty;
    const check = currentEnemy.rollCheck;
    const success = totalRoll >= check;

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

    if (success) {
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
