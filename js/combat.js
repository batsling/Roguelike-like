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
    alert('You have been defeated! Game Over.');
  }
}

// ===== DICE ROLLING =====

function rollD20() {
  if (currentEnemy) {
    currentRoll = Math.floor(Math.random() * 20) + 1;

    // Apply stat modifiers
    let modifier = 0;
    const stat = currentEnemy.stat;

    switch(stat) {
      case 'Strength': modifier = strength; break;
      case 'Dexterity': modifier = dexterity; break;
      case 'Intelligence': modifier = intelligence; break;
      case 'Charisma': modifier = charisma; break;
    }

    const totalRoll = currentRoll + modifier;
    const check = currentEnemy.rollCheck;
    const success = totalRoll >= check;

    let resultText = `Rolled: ${currentRoll}`;
    if (modifier !== 0) {
      resultText += ` + ${modifier} (${stat}) = ${totalRoll}`;
    }
    resultText += ` vs DC ${check}`;

    if (success) {
      resultText += ' ✓ SUCCESS';
      document.getElementById('rollResult').style.color = '#4CAF50';
    } else {
      resultText += ' ✗ FAILURE';
      document.getElementById('rollResult').style.color = '#ff4444';
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
