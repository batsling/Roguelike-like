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


// ===== CURSE VERIFICATION SYSTEM =====

/**
 * Show curse verification modal for curses that require manual verification
 * Also includes trait effects like Precision Landing and equipped weapon effects
 * @param {Function} onComplete - Callback to run after all verifications are done
 */
function showCurseVerificationModal(onComplete) {
  // Check if player has Precision Landing trait
  const hasPrecisionLanding = gameState && gameState.traits && gameState.traits.includes('precision_landing');

  // Check if player has any weapons in inventory
  const weaponsInInventory = (gameState && gameState.inventory || []).filter(i => i.type === 'Weapon');
  const hasEquippedWeapon = weaponsInInventory.length > 0;

  // Check if player has any boons
  const boons = (gameState.inventory || []).filter(item => item.type === 'Boon');

  // Check for Haste "perfect game" items
  const hastePerfectItems = (gameState.inventory || []).filter(item =>
    item.name === 'Secret Technique Instructions' ||
    item.name === 'Clown Shoes' ||
    item.name === 'Performance Based Health Insurance' ||
    item.name === 'Steady Investment'
  );
  const hasHastePerfectItems = hastePerfectItems.length > 0;

  // Check if player is in a Caves of Qud location
  const isInCavesOfQud = gameState.location && typeof hasAppearanceEffect === 'function' && hasAppearanceEffect(gameState.location);

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

  // Check for level up opportunity (character always has a level up condition)
  const characterKey = window.selectedCharacter || (gameState && gameState.character) || 'Rodney';
  const characterData = typeof PLAYER_CHARACTERS !== 'undefined' ? PLAYER_CHARACTERS[characterKey] : null;
  const canLevelUp = characterData && characterData.levelUpCondition;

  // If no curses to verify, no Precision Landing trait, no equipped weapon, no boons, not in Caves of Qud, no level up, and no Haste perfect items, skip verification
  if (cursesToVerify.length === 0 && !hasPrecisionLanding && !hasEquippedWeapon && boons.length === 0 && !isInCavesOfQud && !canLevelUp && !hasHastePerfectItems) {
    if (onComplete) onComplete();
    return;
  }

  // Show combined verification modal for all curses and traits at once
  verifyCursesCombined(cursesToVerify, hasPrecisionLanding, onComplete, canLevelUp, characterData, hastePerfectItems);
}

/**
 * Verify all manual curses, trait effects, weapon effects, and level up in a single combined modal
 * @param {Array} cursesToVerify - Array of curses that need verification
 * @param {boolean} hasPrecisionLanding - Whether player has Precision Landing trait
 * @param {Function} onComplete - Callback to run after verification is done
 * @param {boolean} canLevelUp - Whether character can level up
 * @param {Object} characterData - Character data with levelUpCondition
 * @param {Array} hastePerfectItems - Array of Haste "perfect game" items in inventory
 */
function verifyCursesCombined(cursesToVerify, hasPrecisionLanding, onComplete, canLevelUp = false, characterData = null, hastePerfectItems = []) {
  // Group curses by type in one pass (avoids 11 separate filter calls)
  const _curseTypes = ['blindness','hubris','devotion','greed','impulse','haste','guilt','dazed','affection','hunter','damp'];
  const _curseGroups = {};
  for (const c of cursesToVerify) {
    const lower = c.name.toLowerCase();
    for (const t of _curseTypes) { if (lower.includes(t)) { (_curseGroups[t] = _curseGroups[t] || []).push(c); } }
  }
  const blindnessCurses  = _curseGroups.blindness  || [];
  const hubrisCurses     = _curseGroups.hubris      || [];
  const devotionCurses   = _curseGroups.devotion    || [];
  const greedCurses      = _curseGroups.greed       || [];
  const impulseCurses    = _curseGroups.impulse      || [];
  const hasteCurses      = _curseGroups.haste        || [];
  const guiltCurses      = _curseGroups.guilt        || [];
  const dazedCurses      = _curseGroups.dazed        || [];
  const affectionCurses  = _curseGroups.affection    || [];
  const hunterCurses     = _curseGroups.hunter       || [];
  const dampCurses       = _curseGroups.damp         || [];

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

  // Add Haste Perfect Game section if player has any Haste perfect items
  if (hastePerfectItems.length > 0) {
    // Build reward description based on items
    const rewardParts = [];
    const hasSecretTechnique = hastePerfectItems.some(i => i.name === 'Secret Technique Instructions');
    const hasClownShoes = hastePerfectItems.some(i => i.name === 'Clown Shoes');
    const hasHealthInsurance = hastePerfectItems.some(i => i.name === 'Performance Based Health Insurance');
    const hasSteadyInvestment = hastePerfectItems.some(i => i.name === 'Steady Investment');

    // Count stacks
    const secretTechniqueCount = hastePerfectItems.filter(i => i.name === 'Secret Technique Instructions').length;
    const healthInsuranceCount = hastePerfectItems.filter(i => i.name === 'Performance Based Health Insurance').length;
    const steadyInvestmentCount = hastePerfectItems.filter(i => i.name === 'Steady Investment').length;

    if (hasSecretTechnique) rewardParts.push(`+${secretTechniqueCount} Dash`);
    if (hasHealthInsurance) rewardParts.push(`+${2 * healthInsuranceCount} Health`);
    if (hasSteadyInvestment) rewardParts.push(`+${5 * steadyInvestmentCount} Gold`);

    modalHTML += `
      <div style="background: rgba(255, 215, 0, 0.1); border: 1px solid #ffd700; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #ffd700; margin: 0 0 5px 0; font-size: 15px;">⚡ Perfect Game (Haste Items)</h3>
        <div style="color: #ccaa55; font-size: 11px; margin-bottom: 5px;">
          ${hastePerfectItems.map(i => i.name).join(', ')}
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Beat without losing a run?${rewardParts.length > 0 ? ` Reward: ${rewardParts.join(', ')}` : ''}</p>
        ${hasClownShoes ? `<p style="font-size: 11px; margin: 3px 0; color: #888; font-style: italic;">Clown Shoes: 50% chance to treat "No" as "Yes"</p>` : ''}
        <div style="margin-top: 5px;">
          <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
            <input type="radio" name="haste-perfect-check" value="yes" style="margin-right: 5px;">Yes
          </label>
          <label style="font-size: 12px; color: #ccc;">
            <input type="radio" name="haste-perfect-check" value="no" checked style="margin-right: 5px;">No
          </label>
        </div>
      </div>
    `;
  }

  // Add Weapon Effect section for each weapon in inventory
  const inventoryWeapons = (gameState.inventory || []).filter(i => i.type === 'Weapon');
  if (inventoryWeapons.length > 0) {
    // Resolve (val1/val2/val3) level notation to the value at the given level
    const resolveLevel = (desc, lv) => desc.replace(/\(([^)]+)\)/g, (_, inner) => {
      const parts = inner.split('/').map(s => s.trim());
      return parts[Math.min(lv - 1, parts.length - 1)] || parts[parts.length - 1];
    });

    const getWeaponVerification = (weapon, level) => {
      const lv = level || 1;
      const weaponName = weapon.name;
      // Try to derive question from the weapon's description using "If you …" pattern
      const desc = weapon.description || '';
      const conditionMatch = desc.match(/If you ([^,]+),/i);
      const question = conditionMatch
        ? 'Did you ' + conditionMatch[1].trim() + '?'
        : 'Did you complete the weapon condition?';
      // Resolve the reward text from the description's level notation
      const resolvedDesc = resolveLevel(desc, lv);
      // Extract the reward clause after the comma
      const rewardClause = resolvedDesc.replace(/^[^,]+,\s*/i, '').replace(/^(gain|get)\s+/i, '');
      return { question, reward: rewardClause || 'weapon reward' };
    };

    inventoryWeapons.forEach((weapon, wIdx) => {
      const weaponLevel = weapon.level || 1;
      const { question, reward } = getWeaponVerification(weapon, weaponLevel);
      modalHTML += `
        <div style="background: rgba(255, 152, 0, 0.1); border: 1px solid #ff9800; border-radius: 6px; padding: 10px; margin: 8px 0;">
          <h3 style="color: #ffb74d; margin: 0 0 5px 0; font-size: 15px;">⚔️ ${weapon.name}</h3>
          <div style="color: #cc9966; font-size: 11px; margin-bottom: 5px;">
            Weapon Effect${weaponLevel > 1 ? ` (Lv${weaponLevel})` : ''}
          </div>
          <p style="font-size: 13px; margin: 5px 0; color: #ddd;">${question} <em style="color:#ffb74d;">Reward: ${reward}</em></p>
          <div style="margin-top: 5px;">
            <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
              <input type="radio" name="weapon-check-${wIdx}" value="yes" style="margin-right: 5px;">Yes
            </label>
            <label style="font-size: 12px; color: #ccc;">
              <input type="radio" name="weapon-check-${wIdx}" value="no" checked style="margin-right: 5px;">No
            </label>
          </div>
        </div>
      `;
    });
  }

  // Add Boon verification sections
  const boons = (gameState.inventory || []).filter(item => item.type === 'Boon');
  if (boons.length > 0) {
    boons.forEach((boon, index) => {
      // Parse boon description to get condition
      const getBoonCondition = (description) => {
        // Match everything after "If the player" up to " gain" (non-greedy)
        const conditionMatch = description.match(/If the player ([^,]+?)(?:\s+gain)/i);
        return conditionMatch ? conditionMatch[1] : 'complete the boon condition';
      };

      const condition = getBoonCondition(boon.description);

      modalHTML += `
        <div style="background: rgba(138, 43, 226, 0.15); border: 1px solid #8a2be2; border-radius: 6px; padding: 10px; margin: 8px 0;">
          <h3 style="color: #ba55d3; margin: 0 0 5px 0; font-size: 15px;">🌟 ${boon.name}</h3>
          <div style="color: #9370db; font-size: 11px; margin-bottom: 5px;">
            Boon Effect
          </div>
          <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Did you ${condition}? Reward: +1 to Str, Dex, Int, Cha</p>
          <div style="margin-top: 5px;">
            <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
              <input type="radio" name="boon-check-${index}" value="yes" style="margin-right: 5px;">Yes
            </label>
            <label style="font-size: 12px; color: #ccc;">
              <input type="radio" name="boon-check-${index}" value="no" checked style="margin-right: 5px;">No
            </label>
          </div>
        </div>
      `;
    });
  }

  // Add Caves of Qud appearance change verification (only if in a Caves of Qud location)
  const isInCavesOfQud = gameState.location && typeof hasAppearanceEffect === 'function' && hasAppearanceEffect(gameState.location);
  if (isInCavesOfQud) {
    modalHTML += `
      <div style="background: rgba(102, 187, 106, 0.1); border: 1px solid #66bb6a; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #81c784; margin: 0 0 5px 0; font-size: 15px;">🧬 Appearance Change</h3>
        <div style="color: #a5d6a7; font-size: 11px; margin-bottom: 5px;">
          ${gameState.location.name} Effect
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">Change physical appearance (not attire)? 50/50 upgrade/downgrade random passive</p>
        <div style="margin-top: 5px;">
          <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
            <input type="radio" name="appearance-check" value="yes" style="margin-right: 5px;">Yes
          </label>
          <label style="font-size: 12px; color: #ccc;">
            <input type="radio" name="appearance-check" value="no" checked style="margin-right: 5px;">No
          </label>
        </div>
      </div>
    `;
  }

  // Add Level Up verification section
  if (canLevelUp && characterData) {
    const currentLevel = gameState.playerLevel || 1;
    modalHTML += `
      <div style="background: rgba(255, 215, 0, 0.1); border: 1px solid #FFD700; border-radius: 6px; padding: 10px; margin: 8px 0;">
        <h3 style="color: #FFD700; margin: 0 0 5px 0; font-size: 15px;">⭐ Level Up (Lv.${currentLevel})</h3>
        <div style="color: #ffd54f; font-size: 11px; margin-bottom: 5px;">
          ${characterData.name || 'Character'}
        </div>
        <p style="font-size: 13px; margin: 5px 0; color: #ddd;">${characterData.levelUpCondition}</p>
        <div style="margin-top: 5px;">
          <label style="font-size: 12px; color: #ccc; margin-right: 10px;">
            <input type="radio" name="levelup-check" value="yes" style="margin-right: 5px;">Yes, I did this!
          </label>
          <label style="font-size: 12px; color: #ccc;">
            <input type="radio" name="levelup-check" value="no" checked style="margin-right: 5px;">No
          </label>
        </div>
      </div>
    `;
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

    // Collect a notification for each verification result so the user can see what each curse / weapon /
    // boon / trait outcome did. They fire in sequence after the modal closes (and feed the history tab).
    const verifyNotifs = [];
    const noteVerify = (text, color, icon) => verifyNotifs.push({ text, color, icon });

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
        noteVerify(`Blindness: implemented (${blindnessCurses.length}× progress)`, '#4caf50', '👁️');
      } else {
        noteVerify(`Blindness: not implemented`, '#888', '👁️');
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
          noteVerify(`Hubris (Low): implemented`, '#4caf50', '👑');
        } else {
          noteVerify(`Hubris (Low): not implemented`, '#888', '👑');
        }
      }

      if (hubrisMed.length > 0) {
        const medRadio = document.querySelector('input[name="hubris-med-check"]:checked');
        const didImplement = medRadio && medRadio.value === 'yes';
        if (didImplement) {
          hubrisMed.forEach(curse => {
            gameState.restrictionCursesProcessed.push(curse.id);
          });
          noteVerify(`Hubris (Medium): implemented`, '#4caf50', '👑');
        } else {
          noteVerify(`Hubris (Medium): not implemented`, '#888', '👑');
        }
      }

      if (hubrisHigh.length > 0) {
        const highRadio = document.querySelector('input[name="hubris-high-check"]:checked');
        const didImplement = highRadio && highRadio.value === 'yes';
        if (didImplement) {
          hubrisHigh.forEach(curse => {
            gameState.restrictionCursesProcessed.push(curse.id);
          });
          noteVerify(`Hubris (High): implemented`, '#4caf50', '👑');
        } else {
          noteVerify(`Hubris (High): not implemented`, '#888', '👑');
        }
      }
    }

    // Process Devotion curses
    if (devotionCurses.length > 0) {
      const resetCount = parseInt(document.getElementById('devotion-reset-count').value) || 0;
      const devotionDamagePerReset = devotionCurses.reduce((sum, curse) => {
        return sum + getPowerValue(curse.power, { Low: 1, Medium: 2, High: 3 });
      }, 0);
      const devotionDmg = resetCount * devotionDamagePerReset;
      totalDamage += devotionDmg;
      if (devotionDmg > 0) {
        noteVerify(`Devotion: -${devotionDmg} HP (${resetCount} reset${resetCount === 1 ? '' : 's'})`, '#e74c3c', '🙏');
      } else {
        noteVerify(`Devotion: no resets`, '#888', '🙏');
      }
    }

    // Process Greed curses
    if (greedCurses.length > 0) {
      const skipCount = parseInt(document.getElementById('greed-skip-count').value) || 0;
      const greedDamagePerSkip = greedCurses.reduce((sum, curse) => {
        return sum + getPowerValue(curse.power, { Low: 1, Medium: 2, High: 3 });
      }, 0);
      const greedDmg = skipCount * greedDamagePerSkip;
      totalDamage += greedDmg;
      if (greedDmg > 0) {
        noteVerify(`Greed: -${greedDmg} HP (${skipCount} skip${skipCount === 1 ? '' : 's'})`, '#e74c3c', '💰');
      } else {
        noteVerify(`Greed: no skips`, '#888', '💰');
      }
    }

    // Process Impulse curses
    if (impulseCurses.length > 0) {
      const badPickCount = parseInt(document.getElementById('impulse-bad-pick-count').value) || 0;
      const impulseDamagePerPick = impulseCurses.reduce((sum, curse) => {
        return sum + getPowerValue(curse.power, { Low: 1, Medium: 2, High: 3 });
      }, 0);
      const impulseDmg = badPickCount * impulseDamagePerPick;
      totalDamage += impulseDmg;
      if (impulseDmg > 0) {
        noteVerify(`Impulse: -${impulseDmg} HP (${badPickCount} bad pick${badPickCount === 1 ? '' : 's'})`, '#e74c3c', '⚡');
      } else {
        noteVerify(`Impulse: no bad picks`, '#888', '⚡');
      }
    }

    // Process Haste curses (2 damage per curse if failed)
    if (hasteCurses.length > 0) {
      const hasteRadio = document.querySelector('input[name="haste-check"]:checked');
      const beatInTime = hasteRadio && hasteRadio.value === 'yes';
      if (!beatInTime) {
        const dmg = 2 * hasteCurses.length;
        totalDamage += dmg;
        noteVerify(`Haste: -${dmg} HP (didn't beat in time)`, '#e74c3c', '⏱️');
      } else {
        hasteCurses.forEach(curse => {
          gameState.restrictionCursesProcessed.push(curse.id);
        });
        noteVerify(`Haste: beat in time`, '#4caf50', '⏱️');
      }
    }

    // Process Guilt curses (3 damage per curse if killed innocents)
    if (guiltCurses.length > 0) {
      const guiltRadio = document.querySelector('input[name="guilt-check"]:checked');
      const killedInnocents = guiltRadio && guiltRadio.value === 'yes';
      if (killedInnocents) {
        const dmg = 3 * guiltCurses.length;
        totalDamage += dmg;
        noteVerify(`Guilt: -${dmg} HP (killed innocents)`, '#e74c3c', '😔');
      } else {
        guiltCurses.forEach(curse => {
          gameState.restrictionCursesProcessed.push(curse.id);
        });
        noteVerify(`Guilt: spared innocents`, '#4caf50', '😇');
      }
    }

    // Process Dazed curses (3 damage per curse if didn't beat game twice)
    if (dazedCurses.length > 0) {
      const dazedRadio = document.querySelector('input[name="dazed-check"]:checked');
      const beatTwice = dazedRadio && dazedRadio.value === 'yes';
      if (!beatTwice) {
        const dmg = 3 * dazedCurses.length;
        totalDamage += dmg;
        noteVerify(`Dazed: -${dmg} HP (didn't beat game twice)`, '#e74c3c', '😵');
      } else {
        dazedCurses.forEach(curse => {
          gameState.restrictionCursesProcessed.push(curse.id);
        });
        noteVerify(`Dazed: beat game twice`, '#4caf50', '😵');
      }
    }

    // Process Affection curses (+1 HP if 8+, -2 HP if not, per curse)
    if (affectionCurses.length > 0) {
      const affectionRadio = document.querySelector('input[name="affection-check"]:checked');
      const rated8Plus = affectionRadio && affectionRadio.value === 'yes';
      if (rated8Plus) {
        StateMutator.modifyHealth(affectionCurses.length);
        affectionCurses.forEach(curse => {
          gameState.restrictionCursesProcessed.push(curse.id);
        });
        noteVerify(`Affection: +${affectionCurses.length} HP (rated 8+)`, '#4caf50', '💖');
      } else {
        const dmg = 2 * affectionCurses.length;
        totalDamage += dmg;
        noteVerify(`Affection: -${dmg} HP (rated below 8)`, '#e74c3c', '💔');
      }
    }

    // Process Hunter curses (2 damage per curse if no achievement)
    if (hunterCurses.length > 0) {
      const hunterRadio = document.querySelector('input[name="hunter-check"]:checked');
      const gotAchievement = hunterRadio && hunterRadio.value === 'yes';
      if (!gotAchievement) {
        const dmg = 2 * hunterCurses.length;
        totalDamage += dmg;
        noteVerify(`Hunter: -${dmg} HP (no achievement)`, '#e74c3c', '🏹');
      } else {
        hunterCurses.forEach(curse => {
          gameState.restrictionCursesProcessed.push(curse.id);
        });
        noteVerify(`Hunter: got achievement`, '#4caf50', '🏹');
      }
    }

    // Process Damp curses (3 damage per curse if didn't touch water)
    if (dampCurses.length > 0) {
      const dampRadio = document.querySelector('input[name="damp-check"]:checked');
      const touchedWater = dampRadio && dampRadio.value === 'yes';
      if (!touchedWater) {
        const dmg = 3 * dampCurses.length;
        totalDamage += dmg;
        noteVerify(`Damp: -${dmg} HP (didn't touch water)`, '#e74c3c', '💧');
      } else {
        dampCurses.forEach(curse => {
          gameState.restrictionCursesProcessed.push(curse.id);
        });
        noteVerify(`Damp: touched water`, '#4caf50', '💧');
      }
    }

    // Track whether Precision Landing was activated for notification later
    let precisionLandingActivated = false;
    if (hasPrecisionLanding) {
      const precisionRadio = document.querySelector('input[name="precision-check"]:checked');
      const perfectGame = precisionRadio && precisionRadio.value === 'yes';
      if (perfectGame) {
        StateMutator.modifyAbility('dash', 1);
        precisionLandingActivated = true;
        noteVerify(`Precision Landing: +1 Dash!`, '#00bfff', '🎯');
      } else {
        noteVerify(`Precision Landing: not a perfect game`, '#888', '🎯');
      }
    }

    // Track Haste perfect items activation for notification later
    let hastePerfectActivated = false;
    let hastePerfectRewards = [];
    if (hastePerfectItems.length > 0) {
      const hasteRadio = document.querySelector('input[name="haste-perfect-check"]:checked');
      let perfectGame = hasteRadio && hasteRadio.value === 'yes';

      // Clown Shoes: 50% chance to treat "No" as "Yes"
      const clownShoesCount = hastePerfectItems.filter(i => i.name === 'Clown Shoes').length;
      if (!perfectGame && clownShoesCount > 0) {
        // Each Clown Shoes gives 50% chance
        for (let i = 0; i < clownShoesCount; i++) {
          if (Math.random() < 0.5) {
            perfectGame = true;
            hastePerfectRewards.push('Clown Shoes activated!');
            break;
          }
        }
      }

      if (perfectGame) {
        hastePerfectActivated = true;

        // Secret Technique Instructions: +1 Dash per copy
        const secretTechniqueCount = hastePerfectItems.filter(i => i.name === 'Secret Technique Instructions').length;
        if (secretTechniqueCount > 0) {
          StateMutator.modifyAbility('dash', secretTechniqueCount);
          hastePerfectRewards.push(`+${secretTechniqueCount} Dash`);
        }

        // Performance Based Health Insurance: +5 Health per copy
        const healthInsuranceCount = hastePerfectItems.filter(i => i.name === 'Performance Based Health Insurance').length;
        if (healthInsuranceCount > 0) {
          const healthGain = 5 * healthInsuranceCount;
          StateMutator.modifyHealth(healthGain);
          hastePerfectRewards.push(`+${healthGain} Health`);
        }

        // Steady Investment: +5 Gold per copy
        const steadyInvestmentCount = hastePerfectItems.filter(i => i.name === 'Steady Investment').length;
        if (steadyInvestmentCount > 0) {
          const goldGain = 5 * steadyInvestmentCount;
          StateMutator.modifyGold(goldGain);
          hastePerfectRewards.push(`+${goldGain} Gold`);
        }

        if (typeof updateTopBar === 'function') {
          updateTopBar();
        }
        if (typeof updateGameStats === 'function') {
          updateGameStats();
        }
        noteVerify(`Perfect Game: ${hastePerfectRewards.join(', ')}!`, '#ffd700', '⚡');
      } else {
        noteVerify(`Perfect Game: not earned`, '#888', '⚡');
      }
    }

    // Track weapon effect activation for notification later
    let weaponEffectActivated = false;
    let weaponRewardText = '';
    const verifyInventoryWeapons = (gameState.inventory || []).filter(i => i.type === 'Weapon');
    verifyInventoryWeapons.forEach((weapon, wIdx) => {
      const weaponRadio = document.querySelector(`input[name="weapon-check-${wIdx}"]:checked`);
      const conditionMet = weaponRadio && weaponRadio.value === 'yes';
      if (!conditionMet) {
        noteVerify(`${weapon.name}: condition not met`, '#888', '⚔️');
        return;
      }

      const weaponLevel = weapon.level || 1;

      // Parse the numeric increment for this level from "(+val1/+val2)" notation in the description.
      const parseIncrement = (desc, lv) => {
        const match = (desc || '').match(/\(\+?(\d+)\/\+?(\d+)[^)]*\)/);
        if (match) {
          const vals = [parseInt(match[1]), parseInt(match[2])];
          return vals[Math.min(lv - 1, vals.length - 1)];
        }
        return lv; // fallback: level number
      };
      const increment = parseIncrement(weapon.description || '', weaponLevel);

      // Update ALL copies of the weapon card in the deck (player may have multiples)
      const applyCardBonus = (cardName, pattern, bonus) => {
        if (!gameState.deck) return;
        let updated = false;
        gameState.deck
          .filter(c => c.name === cardName && (c.tags || []).includes('weapon'))
          .forEach(card => {
            card.description = card.description.replace(
              pattern,
              (match, num) => match.replace(num, String(parseInt(num) + bonus))
            );
            updated = true;
          });
        if (updated && typeof saveCurrentGame === 'function') saveCurrentGame();
      };

      // Helper to parse the level value from "(val1/val2/val3)" notation in weapon descriptions
      const resolveWeaponLevel = (desc, lv) => desc.replace(/\(([^)]+)\)/g, (_, inner) => {
        const parts = inner.split('/').map(s => s.trim());
        return parts[Math.min(lv - 1, parts.length - 1)] || parts[parts.length - 1];
      });
      const resolvedEffectDesc = resolveWeaponLevel(weapon.description || '', weaponLevel);
      // Extract the reward clause text (after the first comma)
      const rewardClauseText = resolvedEffectDesc.replace(/^[^,]+,\s*/i, '').replace(/^(gain|get)\s+/i, '') || 'weapon reward';

      if (weapon.name === 'Blasma Pistol') {
        const chestType = weaponLevel === 1 ? 'small' : 'normal';
        gameState._blasmaPistolChest = chestType;
        weaponRewardText = rewardClauseText;
        weaponEffectActivated = true;

      } else if (weapon.name === "Lil' Bomber") {
        applyCardBonus("Lil' Bomber", /Deal (\d+) Dmg/i, increment);
        weaponRewardText = rewardClauseText;
        weaponEffectActivated = true;

      } else if (weapon.name === "Barrel") {
        const fishCount = increment;
        if (typeof selectRandomFish === 'function' && typeof addToLoot === 'function') {
          for (let i = 0; i < fishCount; i++) {
            const fishResult = selectRandomFish(gameState.location);
            addToLoot(fishResult);
          }
        }
        weaponRewardText = rewardClauseText;
        weaponEffectActivated = true;

      } else if (weapon.name === "Blood Magic") {
        applyCardBonus("Blood Magic", /(\d+) Infuse/i, increment);
        weaponRewardText = rewardClauseText;
        weaponEffectActivated = true;

      } else if (weapon.name === "Dexecutioner") {
        applyCardBonus("Dexecutioner", /(\d+) Assassinate/i, increment);
        weaponRewardText = rewardClauseText;
        weaponEffectActivated = true;

      } else if (weapon.name === "Rusty Razor") {
        // Gains (+1/+2) Bleed AND Poison — apply to both stats
        applyCardBonus("Rusty Razor", /Inflict (\d+) Bleed/i, increment);
        applyCardBonus("Rusty Razor", /and (\d+) Poison/i, increment);
        weaponRewardText = rewardClauseText;
        weaponEffectActivated = true;

      } else if (weapon.name === "Bag o' Glitter") {
        applyCardBonus("Bag o' Glitter", /Inflict (\d+) Blind/i, increment);
        weaponRewardText = rewardClauseText;
        weaponEffectActivated = true;

      } else if (weapon.name === "Lower Case r") {
        applyCardBonus("Lower Case r", /Deal (\d+) Dmg/i, increment);
        weaponRewardText = rewardClauseText;
        weaponEffectActivated = true;
      }

      // Per-weapon success notification (one per earned weapon — distinct from the
      // legacy single setTimeout below, which only captured the last weapon).
      noteVerify(`${weapon.name}: Earned ${rewardClauseText}!`, '#ff9800', '⚔️');
    });

    // Process Boon verifications
    const activeBoons = (gameState.inventory || []).filter(item => item.type === 'Boon');
    const activatedBoons = [];
    if (activeBoons.length > 0) {
      activeBoons.forEach((boon, index) => {
        const boonRadio = document.querySelector(`input[name="boon-check-${index}"]:checked`);
        const conditionMet = boonRadio && boonRadio.value === 'yes';
        if (conditionMet) {
          // Grant +1 to all combat roll bonus stats (Str/Dex/Int/Cha, not Attack)
          StateMutator.modifyStat('strength', 1);
          StateMutator.modifyStat('dexterity', 1);
          StateMutator.modifyStat('intelligence', 1);
          StateMutator.modifyStat('charisma', 1);


          // Guarantee at least 1 game choice will have the boon's status applied
          const statusMatch = boon.description.match(/will be (\w+)/);
          if (statusMatch) {
            const statusName = statusMatch[1];
            if (!gameState.pendingLocationStatuses) {
              gameState.pendingLocationStatuses = [];
            }
            gameState.pendingLocationStatuses.push(statusName);
          }

          activatedBoons.push(boon.name);
          noteVerify(`${boon.name}: +1 Str, Dex, Int, Cha!`, '#8a2be2', '🌟');
        } else {
          noteVerify(`${boon.name}: condition not met`, '#888', '🌟');
        }
      });

      // Update UI if any stats changed
      if (activatedBoons.length > 0 && typeof updateTopBar === 'function') {
        updateTopBar();
      }
    }

    // Process Caves of Qud appearance change verification
    let appearanceChangeResult = null;
    if (isInCavesOfQud) {
      const appearanceRadio = document.querySelector('input[name="appearance-check"]:checked');
      const changedAppearance = appearanceRadio && appearanceRadio.value === 'yes';
      if (changedAppearance && typeof upgradeOrDowngradePassive === 'function') {
        // 50/50 chance to upgrade or downgrade
        const isUpgrade = Math.random() < 0.5;
        appearanceChangeResult = upgradeOrDowngradePassive(isUpgrade);
      } else if (!changedAppearance) {
        noteVerify(`Appearance Change: did not change`, '#888', '🧬');
      }
    }

    // Process Level Up verification
    let leveledUp = false;
    if (canLevelUp && characterData) {
      const levelUpRadio = document.querySelector('input[name="levelup-check"]:checked');
      if (levelUpRadio && levelUpRadio.value === 'yes') {
        leveledUp = true;
        noteVerify(`Level Up: condition met!`, '#FFD700', '⭐');
        // Stats and reward modal are handled by confirmLevelUp() below
      } else {
        noteVerify(`Level Up: condition not met`, '#888', '⭐');
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

      StateMutator.modifyHealth(-totalDamage);

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

    // Appearance change result has its own outcome details — push into the unified queue.
    if (appearanceChangeResult) {
      if (appearanceChangeResult.success) {
        const actionText = appearanceChangeResult.isUpgrade ? 'Upgraded' : 'Downgraded';
        noteVerify(`Appearance Changed: ${actionText} ${appearanceChangeResult.itemName}!`, '#66bb6a', '🧬');
      } else {
        noteVerify('Appearance Changed: No passive items to modify', '#888', '🧬');
      }
    }

    // Fire all collected verification notifications in sequence so each one
    // stacks visibly and lands in the notification history tab.
    verifyNotifs.forEach((n, i) => {
      setTimeout(() => {
        if (typeof createNotification === 'function') {
          createNotification(n.text, n.color, n.icon);
        }
      }, 100 + i * 150);
    });

    // Helper function to continue to rewards after all level-up stuff is done
    const continueToRewards = () => {
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

    // If the player leveled up, show the confirmLevelUp modal (applies stats + reward),
    // then continue to normal rewards. Otherwise go straight to rewards.
    if (leveledUp && typeof window.confirmLevelUp === 'function') {
      window.confirmLevelUp(continueToRewards);
    } else {
      continueToRewards();
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
    StateMutator.modifyAbility('dash', 1);

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
