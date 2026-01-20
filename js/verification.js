/**
 * VERIFICATION.JS - Curse, Trait, and Weapon Verification Modals
 *
 * Responsibilities:
 * - Displaying combined verification modal for manual/restriction curses
 * - Handling Precision Landing trait verification
 * - Handling equipped weapon effect verification
 * - Processing verification inputs and applying damage/rewards
 * - Death screen for curse-related deaths
 *
 * Key Functions:
 * - showCurseVerificationModal(onComplete) - Main entry point for verification
 * - verifyCursesCombined(cursesToVerify, hasPrecisionLanding, onComplete) - Combined modal
 * - showPerfectGameVerificationModal(onComplete) - Legacy Precision Landing modal
 * - showDeathScreen(message, source) - Curse death screen
 */

console.log('✅ VERIFICATION.JS v8 loaded - weapon verification trigger active');

// ===== CURSE VERIFICATION SYSTEM =====

/**
 * Show curse verification modal for curses that require manual verification
 * Also includes trait effects like Precision Landing and equipped weapon effects
 * @param {Function} onComplete - Callback to run after all verifications are done
 */
function showCurseVerificationModal(onComplete) {
  // Check if player has Precision Landing trait
  const hasPrecisionLanding = gameState && gameState.traits && gameState.traits.includes('precision_landing');

  // Check if player has an equipped weapon
  const hasEquippedWeapon = gameState && gameState.equippedWeapon;

  // Check if player has any boons
  const boons = (gameState.inventory || []).filter(item => item.type === 'Boon');

  // Get curses that need verification (manual and restriction curses)
  const cursesToVerify = (gameState.activeCurses || []).filter(curse =>
    curse.name.toLowerCase().includes('devotion') ||
    curse.name.toLowerCase().includes('greed') ||
    curse.name.toLowerCase().includes('impulse') ||
    curse.name.toLowerCase().includes('haste') ||
    curse.name.toLowerCase().includes('guilt') ||
    curse.name.toLowerCase().includes('blindness') ||
    curse.name.toLowerCase().includes('hubris') ||
    curse.name.toLowerCase().includes('dazed') ||
    curse.name.toLowerCase().includes('affection') ||
    curse.name.toLowerCase().includes('hunter') ||
    curse.name.toLowerCase().includes('damp')
  );

  // If no curses to verify, no Precision Landing trait, no equipped weapon, and no boons, skip verification
  if (cursesToVerify.length === 0 && !hasPrecisionLanding && !hasEquippedWeapon && boons.length === 0) {
    if (onComplete) onComplete();
    return;
  }

  // Show combined verification modal for all curses and traits at once
  verifyCursesCombined(cursesToVerify, hasPrecisionLanding, onComplete);
}

/**
 * Verify all manual curses, trait effects, and weapon effects in a single combined modal
 * @param {Array} cursesToVerify - Array of curses that need verification
 * @param {boolean} hasPrecisionLanding - Whether player has Precision Landing trait
 * @param {Function} onComplete - Callback to run after verification is done
 */
function verifyCursesCombined(cursesToVerify, hasPrecisionLanding, onComplete) {
  // Group curses by type
  const blindnessCurses = cursesToVerify.filter(c => c.name.toLowerCase().includes('blindness'));
  const hubrisCurses = cursesToVerify.filter(c => c.name.toLowerCase().includes('hubris'));
  const devotionCurses = cursesToVerify.filter(c => c.name.toLowerCase().includes('devotion'));
  const greedCurses = cursesToVerify.filter(c => c.name.toLowerCase().includes('greed'));
  const impulseCurses = cursesToVerify.filter(c => c.name.toLowerCase().includes('impulse'));
  const hasteCurses = cursesToVerify.filter(c => c.name.toLowerCase().includes('haste'));
  const guiltCurses = cursesToVerify.filter(c => c.name.toLowerCase().includes('guilt'));
  const dazedCurses = cursesToVerify.filter(c => c.name.toLowerCase().includes('dazed'));
  const affectionCurses = cursesToVerify.filter(c => c.name.toLowerCase().includes('affection'));
  const hunterCurses = cursesToVerify.filter(c => c.name.toLowerCase().includes('hunter'));
  const dampCurses = cursesToVerify.filter(c => c.name.toLowerCase().includes('damp'));

  // Build the modal HTML with compact styling
  let modalHTML = `
    <div style="text-align: center;">
      <h2 style="color: #ff4444; margin-top: 0; font-size: 24px;">😈 Game Completion Verification</h2>
      <p style="color: #aaa; font-size: 12px; margin: 5px 0;">Answer honestly for each active curse and trait effect</p>
  `;

  // Add Blindness section (restriction curse - purple)
  if (blindnessCurses.length > 0) {
    modalHTML += `
      <div style="background: rgba(170, 102, 255, 0.1); border: 1px solid #aa66ff; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #bb99ff; margin: 0 0 5px 0; font-size: 15px;">🎲 Blindness</h3>
        <div style="color: #aa88cc; font-size: 11px; margin-bottom: 5px;">
          ${blindnessCurses.map(c => c.name).join(', ')}
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Randomly choose character/loadout?</p>
        <div style="margin-top: 5px;">
          <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
            <input type="radio" name="blindness-check" value="yes" checked style="margin-right: 5px;">Yes, did it
          </label>
          <label style="font-size: 12px; color: #ccc;">
            <input type="radio" name="blindness-check" value="no" style="margin-right: 5px;">No/Not possible
          </label>
        </div>
      </div>
    `;
  }

  // Add Hubris sections (restriction curse - purple) - one per tier
  if (hubrisCurses.length > 0) {
    // Group Hubris by tier
    const hubrisLow = hubrisCurses.filter(c => c.power === 'Low');
    const hubrisMed = hubrisCurses.filter(c => c.power === 'Medium');
    const hubrisHigh = hubrisCurses.filter(c => c.power === 'High');

    // Add section for each tier that exists
    if (hubrisLow.length > 0) {
      modalHTML += `
        <div style="background: rgba(170, 102, 255, 0.1); border: 1px solid #aa66ff; border-radius: 6px; padding: 10px; margin: 8px 0;">
          <h3 style="color: #bb99ff; margin: 0 0 5px 0; font-size: 15px;">💪 Hubris I</h3>
          <div style="color: #aa88cc; font-size: 11px; margin-bottom: 5px;">
            ${hubrisLow.map(c => c.name).join(', ')}
          </div>
          <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Raise difficulty once?</p>
          <div style="margin-top: 5px;">
            <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
              <input type="radio" name="hubris-low-check" value="yes" checked style="margin-right: 5px;">Yes, did it
            </label>
            <label style="font-size: 12px; color: #ccc;">
              <input type="radio" name="hubris-low-check" value="no" style="margin-right: 5px;">No/Not possible
            </label>
          </div>
        </div>
      `;
    }

    if (hubrisMed.length > 0) {
      modalHTML += `
        <div style="background: rgba(170, 102, 255, 0.1); border: 1px solid #aa66ff; border-radius: 6px; padding: 10px; margin: 8px 0;">
          <h3 style="color: #bb99ff; margin: 0 0 5px 0; font-size: 15px;">💪 Hubris II</h3>
          <div style="color: #aa88cc; font-size: 11px; margin-bottom: 5px;">
            ${hubrisMed.map(c => c.name).join(', ')}
          </div>
          <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Raise difficulty twice?</p>
          <div style="margin-top: 5px;">
            <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
              <input type="radio" name="hubris-med-check" value="yes" checked style="margin-right: 5px;">Yes, did it
            </label>
            <label style="font-size: 12px; color: #ccc;">
              <input type="radio" name="hubris-med-check" value="no" style="margin-right: 5px;">No/Not possible
            </label>
          </div>
        </div>
      `;
    }

    if (hubrisHigh.length > 0) {
      modalHTML += `
        <div style="background: rgba(170, 102, 255, 0.1); border: 1px solid #aa66ff; border-radius: 6px; padding: 10px; margin: 8px 0;">
          <h3 style="color: #bb99ff; margin: 0 0 5px 0; font-size: 15px;">💪 Hubris III</h3>
          <div style="color: #aa88cc; font-size: 11px; margin-bottom: 5px;">
            ${hubrisHigh.map(c => c.name).join(', ')}
          </div>
          <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Raise difficulty thrice?</p>
          <div style="margin-top: 5px;">
            <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
              <input type="radio" name="hubris-high-check" value="yes" checked style="margin-right: 5px;">Yes, did it
            </label>
            <label style="font-size: 12px; color: #ccc;">
              <input type="radio" name="hubris-high-check" value="no" style="margin-right: 5px;">No/Not possible
            </label>
          </div>
        </div>
      `;
    }
  }

  // Add Devotion section if there are any Devotion curses
  if (devotionCurses.length > 0) {
    const totalDevotionDamage = devotionCurses.reduce((sum, curse) => {
      return sum + getPowerValue(curse.power, { Low: 1, Medium: 2, High: 3 });
    }, 0);

    modalHTML += `
      <div style="background: rgba(255, 170, 68, 0.1); border: 1px solid #ffaa44; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #ffbb66; margin: 0 0 5px 0; font-size: 15px;">⛓️ Devotion</h3>
        <div style="color: #ccaa88; font-size: 11px; margin-bottom: 5px;">
          ${devotionCurses.map(c => c.name).join(', ')}
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Reset any runs? Penalty: ${totalDevotionDamage} HP/reset</p>
        <input type="number" id="devotion-reset-count" min="0" value="0" style="
          padding: 6px;
          font-size: 14px;
          width: 60px;
          text-align: center;
          background: #333;
          border: 2px solid #666;
          border-radius: 4px;
          color: white;
          margin-top: 5px;
        ">
      </div>
    `;
  }

  // Add Greed section if there are any Greed curses
  if (greedCurses.length > 0) {
    const totalGreedDamage = greedCurses.reduce((sum, curse) => {
      return sum + getPowerValue(curse.power, { Low: 1, Medium: 2, High: 3 });
    }, 0);

    modalHTML += `
      <div style="background: rgba(255, 170, 68, 0.1); border: 1px solid #ffaa44; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #ffbb66; margin: 0 0 5px 0; font-size: 15px;">💰 Greed</h3>
        <div style="color: #ccaa88; font-size: 11px; margin-bottom: 5px;">
          ${greedCurses.map(c => c.name).join(', ')}
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Skip item/upgrade choices? Penalty: ${totalGreedDamage} HP/skip</p>
        <input type="number" id="greed-skip-count" min="0" value="0" style="
          padding: 6px;
          font-size: 14px;
          width: 60px;
          text-align: center;
          background: #333;
          border: 2px solid #666;
          border-radius: 4px;
          color: white;
          margin-top: 5px;
        ">
      </div>
    `;
  }

  // Add Impulse section if there are any Impulse curses
  if (impulseCurses.length > 0) {
    const totalImpulseDamage = impulseCurses.reduce((sum, curse) => {
      return sum + getPowerValue(curse.power, { Low: 1, Medium: 2, High: 3 });
    }, 0);

    modalHTML += `
      <div style="background: rgba(255, 170, 68, 0.1); border: 1px solid #ffaa44; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #ffbb66; margin: 0 0 5px 0; font-size: 15px;">⚡ Impulse</h3>
        <div style="color: #ccaa88; font-size: 11px; margin-bottom: 5px;">
          ${impulseCurses.map(c => c.name).join(', ')}
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Pick non-topmost/leftmost choices? Penalty: ${totalImpulseDamage} HP/bad pick</p>
        <input type="number" id="impulse-bad-pick-count" min="0" value="0" style="
          padding: 6px;
          font-size: 14px;
          width: 60px;
          text-align: center;
          background: #333;
          border: 2px solid #666;
          border-radius: 4px;
          color: white;
          margin-top: 5px;
        ">
      </div>
    `;
  }

  // Add Haste section if there are any Haste curses
  if (hasteCurses.length > 0) {
    // Get the time limit based on lowest tier (most lenient)
    const timeLimit = hasteCurses.some(c => c.power === 'Low') ? 4 :
                      hasteCurses.some(c => c.power === 'Medium') ? 3 : 2;
    const totalHasteDamage = 2 * hasteCurses.length;

    modalHTML += `
      <div style="background: rgba(255, 170, 68, 0.1); border: 1px solid #ffaa44; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #ffbb66; margin: 0 0 5px 0; font-size: 15px;">⏱️ Haste</h3>
        <div style="color: #ccaa88; font-size: 11px; margin-bottom: 5px;">
          ${hasteCurses.map(c => c.name).join(', ')}
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Beat game within ${timeLimit} hours? Penalty: ${totalHasteDamage} HP if failed</p>
        <div style="margin-top: 5px;">
          <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
            <input type="radio" name="haste-check" value="yes" checked style="margin-right: 5px;">Yes
          </label>
          <label style="font-size: 12px; color: #ccc;">
            <input type="radio" name="haste-check" value="no" style="margin-right: 5px;">No
          </label>
        </div>
      </div>
    `;
  }

  // Add Guilt section if there are any Guilt curses
  if (guiltCurses.length > 0) {
    const totalGuiltDamage = 3 * guiltCurses.length;

    modalHTML += `
      <div style="background: rgba(255, 170, 68, 0.1); border: 1px solid #ffaa44; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #ffbb66; margin: 0 0 5px 0; font-size: 15px;">😔 Guilt</h3>
        <div style="color: #ccaa88; font-size: 11px; margin-bottom: 5px;">
          ${guiltCurses.map(c => c.name).join(', ')}
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Kill any innocents? Penalty: ${totalGuiltDamage} HP if yes</p>
        <div style="margin-top: 5px;">
          <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
            <input type="radio" name="guilt-check" value="no" checked style="margin-right: 5px;">No
          </label>
          <label style="font-size: 12px; color: #ccc;">
            <input type="radio" name="guilt-check" value="yes" style="margin-right: 5px;">Yes
          </label>
        </div>
      </div>
    `;
  }

  // Add Dazed section if there are any Dazed curses
  if (dazedCurses.length > 0) {
    modalHTML += `
      <div style="background: rgba(255, 170, 68, 0.1); border: 1px solid #ffaa44; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #ffbb66; margin: 0 0 5px 0; font-size: 15px;">💫 Dazed</h3>
        <div style="color: #ccaa88; font-size: 11px; margin-bottom: 5px;">
          ${dazedCurses.map(c => c.name).join(', ')}
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Beat the game twice? Penalty: 3 HP if no</p>
        <div style="margin-top: 5px;">
          <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
            <input type="radio" name="dazed-check" value="yes" checked style="margin-right: 5px;">Yes
          </label>
          <label style="font-size: 12px; color: #ccc;">
            <input type="radio" name="dazed-check" value="no" style="margin-right: 5px;">No
          </label>
        </div>
      </div>
    `;
  }

  // Add Affection section if there are any Affection curses
  if (affectionCurses.length > 0) {
    modalHTML += `
      <div style="background: rgba(255, 170, 68, 0.1); border: 1px solid #ffaa44; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #ffbb66; margin: 0 0 5px 0; font-size: 15px;">💖 Affection</h3>
        <div style="color: #ccaa88; font-size: 11px; margin-bottom: 5px;">
          ${affectionCurses.map(c => c.name).join(', ')}
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Rate game 8+/10? Gain 1 HP if yes, lose 2 HP if no</p>
        <div style="margin-top: 5px;">
          <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
            <input type="radio" name="affection-check" value="yes" checked style="margin-right: 5px;">Yes (8+)
          </label>
          <label style="font-size: 12px; color: #ccc;">
            <input type="radio" name="affection-check" value="no" style="margin-right: 5px;">No (<8)
          </label>
        </div>
      </div>
    `;
  }

  // Add Hunter section if there are any Hunter curses
  if (hunterCurses.length > 0) {
    modalHTML += `
      <div style="background: rgba(255, 170, 68, 0.1); border: 1px solid #ffaa44; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #ffbb66; margin: 0 0 5px 0; font-size: 15px;">🏹 Hunter</h3>
        <div style="color: #ccaa88; font-size: 11px; margin-bottom: 5px;">
          ${hunterCurses.map(c => c.name).join(', ')}
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Get achievement? Penalty: 2 HP if no</p>
        <div style="margin-top: 5px;">
          <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
            <input type="radio" name="hunter-check" value="yes" checked style="margin-right: 5px;">Yes
          </label>
          <label style="font-size: 12px; color: #ccc;">
            <input type="radio" name="hunter-check" value="no" style="margin-right: 5px;">No
          </label>
        </div>
      </div>
    `;
  }

  // Add Damp section if there are any Damp curses
  if (dampCurses.length > 0) {
    modalHTML += `
      <div style="background: rgba(255, 170, 68, 0.1); border: 1px solid #ffaa44; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #ffbb66; margin: 0 0 5px 0; font-size: 15px;">💧 Damp</h3>
        <div style="color: #ccaa88; font-size: 11px; margin-bottom: 5px;">
          ${dampCurses.map(c => c.name).join(', ')}
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Touch water? Penalty: 3 HP if no</p>
        <div style="margin-top: 5px;">
          <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
            <input type="radio" name="damp-check" value="yes" checked style="margin-right: 5px;">Yes
          </label>
          <label style="font-size: 12px; color: #ccc;">
            <input type="radio" name="damp-check" value="no" style="margin-right: 5px;">No
          </label>
        </div>
      </div>
    `;
  }

  // Add Precision Landing section if player has the trait
  if (hasPrecisionLanding) {
    modalHTML += `
      <div style="background: rgba(0, 191, 255, 0.1); border: 1px solid #00bfff; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #00d4ff; margin: 0 0 5px 0; font-size: 15px;">🎯 Precision Landing</h3>
        <div style="color: #88c8dd; font-size: 11px; margin-bottom: 5px;">
          Trait Effect
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Beat without losing a run? Reward: +1 Dash if yes</p>
        <div style="margin-top: 5px;">
          <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
            <input type="radio" name="precision-check" value="yes" style="margin-right: 5px;">Yes
          </label>
          <label style="font-size: 12px; color: #ccc;">
            <input type="radio" name="precision-check" value="no" checked style="margin-right: 5px;">No
          </label>
        </div>
      </div>
    `;
  }

  // Add Weapon Effect section if player has a weapon equipped
  if (gameState.equippedWeapon) {
    const weapon = gameState.equippedWeapon;
    const weaponLevel = gameState.weaponLevel || 1;

    // Parse weapon effect to get the verification question and reward
    const getWeaponVerification = (description, level, weaponName) => {
      // Special handling for Lil' Bomber
      if (weaponName === "Lil' Bomber") {
        const strengthBonus = level === 1 ? 1 : level === 2 ? 2 : 3;
        return {
          question: 'Did you kill an enemy with a bomb at least one time?',
          reward: `+${strengthBonus} Strength`
        };
      }

      // Special handling for Barrel
      if (weaponName === "Barrel") {
        const fishCount = level === 1 ? 1 : level === 2 ? 2 : 3;
        return {
          question: 'Did you obtain at least 1 fish?',
          reward: `${fishCount} random fish`
        };
      }

      // Special handling for Blasma Pistol
      if (weaponName === "Blasma Pistol") {
        const chestSize = level === 1 ? 'small' : level === 2 ? 'normal' : 'large';
        return {
          question: 'Did you open more than 10 chests?',
          reward: `${chestSize} chest`
        };
      }

      // For other weapons: "If you open more than 10 chests in one run, gain a (lv1:small/lv2:normal/lv3:large) chest"
      // Extract the condition and reward
      const conditionMatch = description.match(/If you ([^,]+),/i);
      const levelPattern = /\(lv1:([^/]+)\/lv2:([^/]+)\/lv3:([^)]+)\)/;
      const rewardMatch = description.match(levelPattern);

      let question = conditionMatch ? conditionMatch[1] : 'complete the weapon condition';
      let reward = 'reward';

      if (rewardMatch) {
        const rewardValue = level === 1 ? rewardMatch[1] : level === 2 ? rewardMatch[2] : rewardMatch[3];
        // Extract the reward type (e.g., "chest" from "small chest")
        const rewardTypeMatch = description.match(/gain a \([^)]+\) (\w+)/);
        const rewardType = rewardTypeMatch ? rewardTypeMatch[1] : 'reward';
        reward = `${rewardValue} ${rewardType}`;
      }

      // Convert to a yes/no question
      question = 'Did you ' + question.trim() + '?';

      return { question, reward };
    };

    const { question, reward } = getWeaponVerification(weapon.description, weaponLevel, weapon.name);

    modalHTML += `
      <div style="background: rgba(255, 152, 0, 0.1); border: 1px solid #ff9800; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #ffb74d; margin: 0 0 5px 0; font-size: 15px;">⚔️ ${weapon.name}</h3>
        <div style="color: #cc9966; font-size: 11px; margin-bottom: 5px;">
          Weapon Effect (Level ${weaponLevel})
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">${question} Reward: ${reward}</p>
        <div style="margin-top: 5px;">
          <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
            <input type="radio" name="weapon-check" value="yes" checked style="margin-right: 5px;">Yes
          </label>
          <label style="font-size: 12px; color: #ccc;">
            <input type="radio" name="weapon-check" value="no" style="margin-right: 5px;">No
          </label>
        </div>
      </div>
    `;
  }

  // Add Boon verification sections
  const boons = (gameState.inventory || []).filter(item => item.type === 'Boon');
  if (boons.length > 0) {
    boons.forEach((boon, index) => {
      // Parse boon description to get condition
      const getBoonCondition = (description) => {
        const conditionMatch = description.match(/If the player ([^,]+)/i);
        return conditionMatch ? conditionMatch[1] : 'complete the boon condition';
      };

      const condition = getBoonCondition(boon.description);

      modalHTML += `
        <div style="background: rgba(138, 43, 226, 0.15); border: 1px solid #8a2be2; border-radius: 6px; padding: 10px; margin: 8px 0;">
          <h3 style="color: #ba55d3; margin: 0 0 5px 0; font-size: 15px;">🌟 ${boon.name}</h3>
          <div style="color: #9370db; font-size: 11px; margin-bottom: 5px;">
            Boon Effect
          </div>
          <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Did you ${condition}? Reward: +1 to all combat stats</p>
          <div style="margin-top: 5px;">
            <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
              <input type="radio" name="boon-check-${index}" value="yes" checked style="margin-right: 5px;">Yes
            </label>
            <label style="font-size: 12px; color: #ccc;">
              <input type="radio" name="boon-check-${index}" value="no" style="margin-right: 5px;">No
            </label>
          </div>
        </div>
      `;
    });
  }

  modalHTML += `
      <button id="verify-all-submit" style="
        padding: 15px 40px;
        background: #d32f2f;
        border: 2px solid #f44336;
        border-radius: 8px;
        color: white;
        cursor: pointer;
        font-weight: bold;
        font-size: 16px;
        margin-top: 10px;
      ">Confirm All</button>
    </div>
  `;

  createGameModal(modalHTML);

  // Focus first available input
  setTimeout(() => {
    const firstInput = document.getElementById('devotion-reset-count') ||
                       document.getElementById('greed-skip-count') ||
                       document.getElementById('impulse-bad-pick-count');
    firstInput?.focus();
  }, 100);

  // Handle submission
  document.getElementById('verify-all-submit').onclick = () => {
    let totalDamage = 0;

    // Track which restriction curses should increment
    // (We'll mark them manually here, then skip them in checkCurseDurations)
    if (!gameState.restrictionCursesProcessed) {
      gameState.restrictionCursesProcessed = [];
    }
    gameState.restrictionCursesProcessed = [];

    // Process Blindness restriction curses
    if (blindnessCurses.length > 0) {
      const blindnessRadio = document.querySelector('input[name="blindness-check"]:checked');
      const didImplement = blindnessRadio && blindnessRadio.value === 'yes';
      if (didImplement) {
        // Mark these curses as should increment
        blindnessCurses.forEach(curse => {
          gameState.restrictionCursesProcessed.push(curse.id);
        });
      }
    }

    // Process Hubris restriction curses by tier
    if (hubrisCurses.length > 0) {
      // Group by tier
      const hubrisLow = hubrisCurses.filter(c => c.power === 'Low');
      const hubrisMed = hubrisCurses.filter(c => c.power === 'Medium');
      const hubrisHigh = hubrisCurses.filter(c => c.power === 'High');

      // Process each tier separately
      if (hubrisLow.length > 0) {
        const lowRadio = document.querySelector('input[name="hubris-low-check"]:checked');
        const didImplement = lowRadio && lowRadio.value === 'yes';
        if (didImplement) {
          hubrisLow.forEach(curse => {
            gameState.restrictionCursesProcessed.push(curse.id);
          });
        }
      }

      if (hubrisMed.length > 0) {
        const medRadio = document.querySelector('input[name="hubris-med-check"]:checked');
        const didImplement = medRadio && medRadio.value === 'yes';
        if (didImplement) {
          hubrisMed.forEach(curse => {
            gameState.restrictionCursesProcessed.push(curse.id);
          });
        }
      }

      if (hubrisHigh.length > 0) {
        const highRadio = document.querySelector('input[name="hubris-high-check"]:checked');
        const didImplement = highRadio && highRadio.value === 'yes';
        console.log(`Hubris III verification: Found ${hubrisHigh.length} curses, didImplement=${didImplement}`);
        if (didImplement) {
          hubrisHigh.forEach(curse => {
            console.log(`Adding Hubris III to restrictionCursesProcessed: ${curse.name} (ID: ${curse.id})`);
            gameState.restrictionCursesProcessed.push(curse.id);
          });
        }
      }
    }

    // Process Devotion curses
    if (devotionCurses.length > 0) {
      const resetCount = parseInt(document.getElementById('devotion-reset-count').value) || 0;
      const devotionDamagePerReset = devotionCurses.reduce((sum, curse) => {
        return sum + getPowerValue(curse.power, { Low: 1, Medium: 2, High: 3 });
      }, 0);
      totalDamage += resetCount * devotionDamagePerReset;
    }

    // Process Greed curses
    if (greedCurses.length > 0) {
      const skipCount = parseInt(document.getElementById('greed-skip-count').value) || 0;
      const greedDamagePerSkip = greedCurses.reduce((sum, curse) => {
        return sum + getPowerValue(curse.power, { Low: 1, Medium: 2, High: 3 });
      }, 0);
      totalDamage += skipCount * greedDamagePerSkip;
    }

    // Process Impulse curses
    if (impulseCurses.length > 0) {
      const badPickCount = parseInt(document.getElementById('impulse-bad-pick-count').value) || 0;
      const impulseDamagePerPick = impulseCurses.reduce((sum, curse) => {
        return sum + getPowerValue(curse.power, { Low: 1, Medium: 2, High: 3 });
      }, 0);
      totalDamage += badPickCount * impulseDamagePerPick;
    }

    // Process Haste curses (2 damage per curse if failed)
    if (hasteCurses.length > 0) {
      const hasteRadio = document.querySelector('input[name="haste-check"]:checked');
      const beatInTime = hasteRadio && hasteRadio.value === 'yes';
      if (!beatInTime) {
        totalDamage += 2 * hasteCurses.length; // 2 damage per Haste curse
      } else {
        // Mark curses for duration increment (completed successfully)
        hasteCurses.forEach(curse => {
          gameState.restrictionCursesProcessed.push(curse.id);
        });
      }
    }

    // Process Guilt curses (3 damage per curse if killed innocents)
    if (guiltCurses.length > 0) {
      const guiltRadio = document.querySelector('input[name="guilt-check"]:checked');
      const killedInnocents = guiltRadio && guiltRadio.value === 'yes';
      if (killedInnocents) {
        totalDamage += 3 * guiltCurses.length; // 3 damage per Guilt curse
      } else {
        // Mark curses for duration increment (didn't kill innocents)
        guiltCurses.forEach(curse => {
          gameState.restrictionCursesProcessed.push(curse.id);
        });
      }
    }

    // Process Dazed curses (3 damage per curse if didn't beat game twice)
    if (dazedCurses.length > 0) {
      const dazedRadio = document.querySelector('input[name="dazed-check"]:checked');
      const beatTwice = dazedRadio && dazedRadio.value === 'yes';
      if (!beatTwice) {
        totalDamage += 3 * dazedCurses.length; // 3 damage per Dazed curse
      } else {
        // Mark curses for duration increment (beat game twice)
        dazedCurses.forEach(curse => {
          gameState.restrictionCursesProcessed.push(curse.id);
        });
      }
    }

    // Process Affection curses (+1 HP if 8+, -2 HP if not, per curse)
    if (affectionCurses.length > 0) {
      const affectionRadio = document.querySelector('input[name="affection-check"]:checked');
      const rated8Plus = affectionRadio && affectionRadio.value === 'yes';
      if (rated8Plus) {
        // Gain 1 health per curse
        health = Math.min(maxHealth, health + affectionCurses.length);
        gameState.health = health;
        updateTopBar?.();
        // Mark curses for duration increment (rated 8+)
        affectionCurses.forEach(curse => {
          gameState.restrictionCursesProcessed.push(curse.id);
        });
      } else {
        // Lose 2 health per curse
        totalDamage += 2 * affectionCurses.length;
      }
    }

    // Process Hunter curses (2 damage per curse if no achievement)
    if (hunterCurses.length > 0) {
      const hunterRadio = document.querySelector('input[name="hunter-check"]:checked');
      const gotAchievement = hunterRadio && hunterRadio.value === 'yes';
      if (!gotAchievement) {
        totalDamage += 2 * hunterCurses.length; // 2 damage per Hunter curse
      } else {
        // Mark curses for duration increment (got achievement)
        hunterCurses.forEach(curse => {
          gameState.restrictionCursesProcessed.push(curse.id);
        });
      }
    }

    // Process Damp curses (3 damage per curse if didn't touch water)
    if (dampCurses.length > 0) {
      const dampRadio = document.querySelector('input[name="damp-check"]:checked');
      const touchedWater = dampRadio && dampRadio.value === 'yes';
      if (!touchedWater) {
        totalDamage += 3 * dampCurses.length; // 3 damage per Damp curse
      } else {
        // Mark curses for duration increment (touched water)
        dampCurses.forEach(curse => {
          gameState.restrictionCursesProcessed.push(curse.id);
        });
      }
    }

    // Track whether Precision Landing was activated for notification later
    let precisionLandingActivated = false;
    if (hasPrecisionLanding) {
      const precisionRadio = document.querySelector('input[name="precision-check"]:checked');
      const perfectGame = precisionRadio && precisionRadio.value === 'yes';
      if (perfectGame) {
        dash = Math.max(0, dash + 1);
        gameState.dash = dash;
        if (typeof updateTopBar === 'function') {
          updateTopBar();
        }
        console.log('Precision Landing activated: +1 Dash');
        precisionLandingActivated = true;
      }
    }

    // Track weapon effect activation for notification later
    let weaponEffectActivated = false;
    let weaponRewardText = '';
    if (gameState.equippedWeapon) {
      const weaponRadio = document.querySelector('input[name="weapon-check"]:checked');
      const conditionMet = weaponRadio && weaponRadio.value === 'yes';
      if (conditionMet) {
        const weaponLevel = gameState.weaponLevel || 1;
        const weapon = gameState.equippedWeapon;

        // Grant reward based on weapon and level
        // For Blasma Pistol: grant small/normal/large chest
        if (weapon.name === 'Blasma Pistol') {
          const chestType = weaponLevel === 1 ? 'small' : weaponLevel === 2 ? 'normal' : 'large';

          // Store that we need to show Blasma chest before normal rewards
          weaponRewardText = `${chestType.charAt(0).toUpperCase() + chestType.slice(1)} Chest`;
          weaponEffectActivated = true;

          // Store chest type for later - we'll show it BEFORE calling onComplete
          gameState._blasmaPistolChest = chestType;

          console.log(`${weapon.name} activated: will grant ${chestType} chest before normal reward`);
        }
        // For Lil' Bomber: grant +1/+2/+3 Strength
        else if (weapon.name === "Lil' Bomber") {
          const strengthBonus = weaponLevel === 1 ? 1 : weaponLevel === 2 ? 2 : 3;

          // Apply strength bonus
          strength += strengthBonus;
          gameState.strength = strength;
          if (typeof updateTopBar === 'function') {
            updateTopBar();
          }

          weaponRewardText = `+${strengthBonus} Strength`;
          weaponEffectActivated = true;

          console.log(`${weapon.name} activated: +${strengthBonus} Strength`);
        }
        // For Barrel: grant 1/2/3 random fish
        else if (weapon.name === "Barrel") {
          const fishCount = weaponLevel === 1 ? 1 : weaponLevel === 2 ? 2 : 3;

          // Give random fish based on location
          if (typeof selectRandomFish === 'function' && typeof addToLoot === 'function') {
            for (let i = 0; i < fishCount; i++) {
              const fishResult = selectRandomFish(gameState.location);
              addToLoot(fishResult);
            }

            weaponRewardText = `${fishCount} random fish`;
            weaponEffectActivated = true;

            console.log(`${weapon.name} activated: granted ${fishCount} random fish`);
          }
        }
      }
    }

    // Process Boon verifications
    const activeBoons = (gameState.inventory || []).filter(item => item.type === 'Boon');
    const activatedBoons = [];
    if (activeBoons.length > 0) {
      activeBoons.forEach((boon, index) => {
        const boonRadio = document.querySelector(`input[name="boon-check-${index}"]:checked`);
        const conditionMet = boonRadio && boonRadio.value === 'yes';
        if (conditionMet) {
          // Grant +1 to all combat stats
          strength += 1;
          dexterity += 1;
          intelligence += 1;
          charisma += 1;
          gameState.strength = strength;
          gameState.dexterity = dexterity;
          gameState.intelligence = intelligence;
          gameState.charisma = charisma;

          console.log(`${boon.name} activated: +1 to all combat stats`);

          // 20% chance to apply status effect to next game
          if (Math.random() < 0.2) {
            // Extract status name from description
            const statusMatch = boon.description.match(/to be (\w+)/);
            if (statusMatch) {
              const statusName = statusMatch[1];
              if (!gameState.pendingLocationStatuses) {
                gameState.pendingLocationStatuses = [];
              }
              gameState.pendingLocationStatuses.push(statusName);
              console.log(`${boon.name}: Next game will have status ${statusName}`);
            }
          }

          activatedBoons.push(boon.name);
        }
      });

      // Update UI if any stats changed
      if (activatedBoons.length > 0 && typeof updateTopBar === 'function') {
        updateTopBar();
      }
    }

    closeGameModal();

    // Immediately increment curse trackers for curses that were completed successfully
    // This provides instant feedback before the normal checkCurseDurations() call
    if (gameState.restrictionCursesProcessed && gameState.restrictionCursesProcessed.length > 0) {
      // Initialize tracker if it doesn't exist
      if (!gameState.cursesTracker) {
        gameState.cursesTracker = {};
      }

      // Track which curses to check for removal
      const cursesToCheckForRemoval = [];

      // Increment each curse that was successfully completed
      gameState.activeCurses.forEach(curse => {
        if (gameState.restrictionCursesProcessed.includes(curse.id)) {
          const trackerId = curse.id || curse.name;
          if (!gameState.cursesTracker[trackerId]) {
            gameState.cursesTracker[trackerId] = { gamesBeaten: 0 };
          }
          gameState.cursesTracker[trackerId].gamesBeaten = (gameState.cursesTracker[trackerId].gamesBeaten || 0) + 1;
          console.log(`✅ Immediately incremented curse ${curse.name} (${curse.id}): ${gameState.cursesTracker[trackerId].gamesBeaten} games beaten`);

          // Check if curse duration is complete
          if (curse.duration) {
            const match = curse.duration.match(/(\d+)\s+game/i);
            if (match) {
              const requiredGames = parseInt(match[1]);
              if (gameState.cursesTracker[trackerId].gamesBeaten >= requiredGames) {
                cursesToCheckForRemoval.push(curse);
              }
            }
          }
        }
      });

      // Remove completed curses immediately
      if (cursesToCheckForRemoval.length > 0 && typeof CurseManager !== 'undefined') {
        cursesToCheckForRemoval.forEach(curse => {
          CurseManager.consume(curse);
          const trackerId = curse.id || curse.name;
          delete gameState.cursesTracker[trackerId];

          if (typeof createNotification === 'function') {
            setTimeout(() => {
              createNotification(`${curse.name} duration complete!`, '#4CAF50', '✨');
            }, 300);
          }
        });
      }

      // Update curse UI immediately to show the new counters
      if (typeof updateCurseUI === 'function') {
        updateCurseUI();
      }

      // Clear the list so checkCurseDurations doesn't try to increment again
      gameState.restrictionCursesProcessed = [];
    }

    // Apply total damage silently
    if (totalDamage > 0) {
      // Apply damage reduction from items (like Garlic)
      if (typeof calculateDamageReduction === 'function') {
        totalDamage = calculateDamageReduction(totalDamage);
      }

      health = Math.max(0, health - totalDamage);
      gameState.health = health;
      updateTopBar?.();

      // Check for death
      if (health <= 0) {
        // Trigger death screen
        inventory = [];
        if (gameState.activeCurses) {
          gameState.activeCurses = [];
        }
        updateInventory?.();
        updateCursesDisplay?.();
        updateActiveCursesList?.();
        showDeathScreen('You succumbed to your curses!', 'curse');
        return; // Don't call onComplete if player died
      }
    }

    // Show Precision Landing notification after modal closes
    if (precisionLandingActivated) {
      setTimeout(() => {
        if (typeof createNotification === 'function') {
          createNotification('Precision Landing: +1 Dash!', '#00bfff', '🎯');
        }
      }, 100);
    }

    // Show weapon effect notification after modal closes
    if (weaponEffectActivated) {
      setTimeout(() => {
        if (typeof createNotification === 'function') {
          createNotification(`${gameState.equippedWeapon.name}: Earned ${weaponRewardText}!`, '#ff9800', '⚔️');
        }
      }, precisionLandingActivated ? 200 : 100); // Delay slightly if Precision Landing also activated
    }

    // Show boon notifications after modal closes
    if (activatedBoons.length > 0) {
      activatedBoons.forEach((boonName, index) => {
        setTimeout(() => {
          if (typeof createNotification === 'function') {
            createNotification(`${boonName}: +1 to All Combat Stats!`, '#8a2be2', '🌟');
          }
        }, (precisionLandingActivated ? 200 : 100) + (weaponEffectActivated ? 100 : 0) + (index * 100));
      });
    }

    // Check if Blasma Pistol chest needs to be shown BEFORE the normal reward
    if (gameState._blasmaPistolChest) {
      const blasmaChestType = gameState._blasmaPistolChest;
      delete gameState._blasmaPistolChest; // Clear the flag

      // Show Blasma Pistol chest first, then continue with normal flow
      if (typeof offerChest === 'function') {
        offerChest(blasmaChestType, () => {
          // After Blasma Pistol chest is complete, continue to normal rewards
          if (onComplete) onComplete();
        });
      } else {
        // Fallback if offerChest not available
        if (onComplete) onComplete();
      }
    } else {
      // No Blasma Pistol chest, continue normally
      if (onComplete) onComplete();
    }
  };
}

// ===== PRECISION LANDING VERIFICATION SYSTEM (LEGACY) =====

/**
 * Show perfect game verification modal for Precision Landing trait
 * NOTE: This is legacy code - Precision Landing is now integrated into verifyCursesCombined()
 * Kept for backwards compatibility
 * @param {Function} onComplete - Callback to run after verification
 */
function showPerfectGameVerificationModal(onComplete) {
  // Check if player has the Precision Landing trait
  if (!gameState || !gameState.traits || !gameState.traits.includes('precision_landing')) {
    if (onComplete) onComplete();
    return;
  }

  // Show verification modal
  const modalHTML = `
    <div style="text-align: center;">
      <h2 style="color: #00bfff; margin-top: 0; font-size: 24px;">🎯 Precision Landing</h2>
      <p style="color: #aaa; font-size: 14px; margin: 10px 0;">Did you beat this game without losing a run once?</p>
      <p style="color: #888; font-size: 12px; margin: 10px 0; font-style: italic;">
        (Gain +1 Dash if yes)
      </p>
      <div style="margin-top: 20px; display: flex; gap: 15px; justify-content: center;">
        <button id="perfect-yes-btn" style="
          padding: 12px 24px;
          background: #4CAF50;
          border: 2px solid #66bb6a;
          border-radius: 8px;
          color: white;
          cursor: pointer;
          font-weight: bold;
          font-size: 16px;
        ">✓ Yes, Perfect Run!</button>
        <button id="perfect-no-btn" style="
          padding: 12px 24px;
          background: #666;
          border: 2px solid #888;
          border-radius: 8px;
          color: white;
          cursor: pointer;
          font-weight: bold;
          font-size: 16px;
        ">✗ No</button>
      </div>
    </div>
  `;

  createGameModal(modalHTML);

  // Handle Yes button
  document.getElementById('perfect-yes-btn').onclick = () => {
    // Grant +1 Dash
    dash += 1;
    gameState.dash = dash;
    if (typeof updateTopBar === 'function') {
      updateTopBar();
    }

    console.log('Precision Landing activated: +1 Dash');

    // Show notification
    setTimeout(() => {
      if (typeof createNotification === 'function') {
        createNotification('Precision Landing: +1 Dash!', '#00bfff', '🎯');
      }
    }, 100);

    closeGameModal();
    if (onComplete) onComplete();
  };

  // Handle No button
  document.getElementById('perfect-no-btn').onclick = () => {
    console.log('Precision Landing not activated (player did not perfect the game)');
    closeGameModal();
    if (onComplete) onComplete();
  };
}

/**
 * Show death screen after curse damage
 */
function showDeathScreen(message = 'You have perished!', source = 'curse') {
  createGameModal(`
    <div style="text-align: center;">
      <h1 style="color: #ff4444; font-size: 48px; margin: 20px 0;">💀 YOU ARE DEAD</h1>
      <p style="color: #aaa; font-size: 18px; margin: 20px 0;">The curse was too much to bear...</p>
      <div style="margin-top: 30px; display: flex; gap: 15px; justify-content: center;">
        <button id="curse-death-home-btn" style="
          padding: 12px 24px;
          background: #444;
          border: 2px solid #666;
          border-radius: 8px;
          color: white;
          cursor: pointer;
          font-weight: bold;
          font-size: 16px;
        ">🏠 Home</button>
      </div>
    </div>
  `);

  document.getElementById('curse-death-home-btn').onclick = () => {
    closeGameModal();
    updateInventory?.();
    updateCursesDisplay?.();
    updateActiveCursesList?.();
    updateGameStats?.();
    if (typeof clearAllArrows === 'function') {
      clearAllArrows();
    }
    document.getElementById('dungeon-screen').style.display = 'none';
    document.getElementById('main-menu').style.display = 'flex';

    // Hide map button when in menu
    const mapBtn = document.getElementById('map-btn');
    if (mapBtn) mapBtn.style.display = 'none';
  };
}

// Export verification functions globally
window.showCurseVerificationModal = showCurseVerificationModal;
