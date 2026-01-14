// ===== UI.JS - All DOM Manipulation and Display Updates =====
//
// This module handles all visual updates to the UI including:
// - Top bar (health, gold, rations)
// - Inventory display

console.log('✅ UI.JS v26 loaded - weapon deep copy fix active + comprehensive debugging');

// Check for equipment slots on DOM ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', () => {
    const weaponSlot = document.getElementById('weapon-slot');
    const amuletSlot = document.getElementById('amulet-slot');
    console.log('🎯 DOM Ready - Equipment slots check:', {
      weaponSlot: !!weaponSlot,
      amuletSlot: !!amuletSlot
    });
  });
} else {
  const weaponSlot = document.getElementById('weapon-slot');
  const amuletSlot = document.getElementById('amulet-slot');
  console.log('🎯 Immediate - Equipment slots check:', {
    weaponSlot: !!weaponSlot,
    amuletSlot: !!amuletSlot
  });
}
// - Game lists and selections
// - Encounter history
// - Game state stats sidebar

// ===== TOP BAR UPDATES =====

function updateTopBar() {
  // Update floating HUD (now at bottom of screen)
  const gameHealth = document.getElementById('game-health');
  const gameGold = document.getElementById('game-gold');

  if (gameHealth) {
    gameHealth.textContent = `${health}/${maxHealth}`;
  }

  if (gameGold) {
    gameGold.textContent = gold;
  }

  // Update stats panel health/gold if they exist
  const statsHealth = document.getElementById('stats-health');
  const statsGold = document.getElementById('stats-gold');

  if (statsHealth) {
    statsHealth.textContent = `${health}/${maxHealth}`;
  }

  if (statsGold) {
    statsGold.textContent = gold;
  }
}

function updateHealthDisplay() {
  // Legacy function - now handled by updateTopBar
  updateTopBar();
}

function updateGoldDisplay() {
  // Legacy function - now handled by updateTopBar
  updateTopBar();
}

// ===== INVENTORY DISPLAY =====

// Global inventory sort mode (default: 'type')
window.inventorySortMode = window.inventorySortMode || 'type';

function updateInventory() {
  const inventoryDiv = document.getElementById('inventory');
  inventoryDiv.innerHTML = '';

  const removeItemSelect = document.getElementById('removeItemSelect');
  removeItemSelect.innerHTML = '<option value="">-- Select an Item --</option>';

  inventory.forEach((item, index) => {
    const itemDiv = document.createElement('div');
    itemDiv.className = 'inventory-item';
    itemDiv.innerHTML = `
      <strong>${item.name}</strong> (${item.rarity})
      <span class="remove-item" onclick="removeItem(${index})">×</span>
      <p>${item.description}</p>
      <p><em>Type: ${item.type}</em></p>
    `;
    inventoryDiv.appendChild(itemDiv);

    const option = document.createElement('option');
    option.value = index;
    option.textContent = `${item.name} (${item.rarity})`;
    removeItemSelect.appendChild(option);
  });

  removeItemSelect.disabled = inventory.length === 0;
  document.getElementById('removeSelectedItem').disabled = inventory.length === 0;
  document.getElementById('removeRandomItem').disabled = inventory.length === 0;

  // Update game items sidebar if it exists
  const gameItemsList = document.getElementById('game-items-list');
  if (gameItemsList) {
    console.log('Updating game-items-list, inventory length:', inventory.length, 'sort mode:', window.inventorySortMode);
    if (inventory.length === 0) {
      gameItemsList.innerHTML = '<div class="empty-inventory">No items yet</div>';
    } else {
      // Sort inventory based on current mode
      // Filter out equipped weapon
      const sortedInventory = [...inventory]
        .map((item, idx) => ({ item, idx }))
        .filter(({ item }) => {
          // Hide equipped weapon from inventory
          return !(gameState.equippedWeapon && item.name === gameState.equippedWeapon.name);
        })
        .sort((a, b) => {
          if (window.inventorySortMode === 'alphabetical') {
            return a.item.name.localeCompare(b.item.name);
          } else if (window.inventorySortMode === 'rarity') {
            const rarityOrder = { 'common': 0, 'uncommon': 1, 'rare': 2, 'epic': 3, 'legendary': 4 };
            const aRarity = rarityOrder[a.item.rarity?.toLowerCase()] ?? 0;
            const bRarity = rarityOrder[b.item.rarity?.toLowerCase()] ?? 0;
            return bRarity - aRarity; // Higher rarity first
          } else {
            // Default: type sort (weapons first, then usable, then passive)
            const typeOrder = { 'Weapon': 0, 'Usable': 1, 'Passive': 2 };
            const aOrder = typeOrder[a.item.type] ?? 3;
            const bOrder = typeOrder[b.item.type] ?? 3;
            return aOrder - bOrder;
          }
        });

      console.log('Sorted inventory order:', sortedInventory.map(x => x.item.name).join(', '));
      console.log('📦 First 3 items with full data:', sortedInventory.slice(0, 3).map(x => ({
        name: x.item.name,
        type: x.item.type,
        rarity: x.item.rarity,
        image: x.item.image
      })));

      gameItemsList.innerHTML = sortedInventory.map(({ item, idx }) => {
        let imageUrl = item.image && item.image.trim() !== ''
          ? item.image
          : 'https://via.placeholder.com/75?text=%3F';

        // Fix imgur URLs
        if (imageUrl.includes('imgur.com/') && !imageUrl.includes('i.imgur.com')) {
          imageUrl = imageUrl.replace('imgur.com/', 'i.imgur.com/');
          if (!imageUrl.match(/\.(png|jpg|jpeg|gif)$/i)) {
            imageUrl += '.png';
          }
        }

        // Get rarity color for border
        const getRarityColor = (rarity) => {
          switch(rarity?.toLowerCase()) {
            case 'legendary': return '#ff6b00';
            case 'rare': return '#9b59b6';
            case 'uncommon': return '#4CAF50';
            case 'common': return '#aaa';
            default: return '#888';
          }
        };

        const rarityColor = getRarityColor(item.rarity);

        const isUsable = item.type === 'Usable';
        const canUse = isUsable && typeof canUseItem === 'function' && canUseItem(item);
        const isWeapon = item.type === 'Weapon';

        return `
          <div class="item-display-container" data-item-index="${idx}" style="
            position: relative;
            display: inline-block;
            transition: transform 0.2s ease;
          ">
            <div class="item-display-image" style="
              cursor: pointer;
              position: relative;
            ">
              <img src="${imageUrl}"
                   alt="${item.name}"
                   loading="lazy"
                   style="width: 75px; height: 75px; object-fit: contain; border-radius: 6px; display: block; background: #1a1a1a; padding: 2px; border: 3px solid ${rarityColor};"
                   onerror="if(this.src!=='https://via.placeholder.com/75?text=%3F'){this.src='https://via.placeholder.com/75?text=%3F';this.classList.add('image-error');}">
              ${item.quantity && item.quantity > 1 ? `
                <div class="item-quantity-badge" style="
                  position: absolute;
                  top: 2px;
                  right: 2px;
                  background: rgba(0, 0, 0, 0.85);
                  color: white;
                  padding: 2px 5px;
                  border-radius: 3px;
                  font-size: 11px;
                  font-weight: bold;
                  border: 1px solid #ffaa00;
                  z-index: 15;
                ">x${item.quantity}</div>
              ` : ''}
              ${isUsable ? `
                <button class="item-use-button"
                        data-item-index="${idx}"
                        style="
                          position: absolute;
                          bottom: 2px;
                          left: 2px;
                          right: 2px;
                          padding: 2px 4px;
                          font-size: 10px;
                          background: ${canUse ? '#4CAF50' : '#555'};
                          color: ${canUse ? 'white' : '#888'};
                          border: 1px solid ${canUse ? '#2E7D32' : '#333'};
                          border-radius: 3px;
                          cursor: ${canUse ? 'pointer' : 'not-allowed'};
                          font-weight: bold;
                          text-transform: uppercase;
                          z-index: 10;
                        "
                        ${!canUse ? 'disabled' : ''}>
                  Use${item.uses && item.uses > 1 ? ` x${item.uses}` : ''}
                </button>
              ` : ''}
              ${isWeapon ? `
                <button class="item-equip-button"
                        data-item-index="${idx}"
                        style="
                          position: absolute;
                          bottom: 2px;
                          left: 2px;
                          right: 2px;
                          padding: 2px 4px;
                          font-size: 10px;
                          background: #ff9800;
                          color: white;
                          border: 1px solid #f57c00;
                          border-radius: 3px;
                          cursor: pointer;
                          font-weight: bold;
                          text-transform: uppercase;
                          z-index: 10;
                        ">
                  Equip
                </button>
              ` : ''}
            </div>
          </div>
        `;
      }).join('');

      // Add tooltip and hover effect event listeners after rendering
      const itemContainers = gameItemsList.querySelectorAll('.item-display-container');
      itemContainers.forEach((container) => {
        const itemIdx = parseInt(container.dataset.itemIndex);
        const div = container.querySelector('.item-display-image');

        // Add hover scale effect
        container.onmouseenter = e => {
          container.style.transform = 'scale(1.1)';
          container.style.zIndex = '100';
          showItemTooltip(e, inventory[itemIdx]);
        };

        container.onmousemove = e => {
          moveItemTooltip(e);
        };

        container.onmouseleave = e => {
          container.style.transform = '';
          container.style.zIndex = '';
          hideItemTooltip();
        };
      });

      // Add use button event listeners
      const useButtons = gameItemsList.querySelectorAll('.item-use-button');
      useButtons.forEach((button) => {
        button.onclick = (e) => {
          e.stopPropagation(); // Prevent triggering tooltip
          const itemIndex = parseInt(button.dataset.itemIndex);
          if (typeof useItem === 'function') {
            useItem(itemIndex);
          }
        };
      });

      // Add equip button event listeners
      const equipButtons = gameItemsList.querySelectorAll('.item-equip-button');
      equipButtons.forEach((button) => {
        button.onclick = (e) => {
          e.stopPropagation(); // Prevent triggering tooltip
          const itemIndex = parseInt(button.dataset.itemIndex);
          equipWeapon(itemIndex);
        };
      });
    }
  }

  // Update stats panel and equipment slots
  updateGameStats();
  updateEquipmentSlots();
}

// ===== WEAPON EQUIP/UNEQUIP FUNCTIONS =====

function equipWeapon(itemIndex) {
  console.log('🔫 equipWeapon called with index:', itemIndex, 'inventory length:', inventory.length);

  if (itemIndex < 0 || itemIndex >= inventory.length) {
    console.error('Invalid item index:', itemIndex);
    return;
  }

  const weapon = inventory[itemIndex];
  console.log('🔫 Weapon from inventory:', weapon);

  if (weapon.type !== 'Weapon') {
    console.error('Item is not a weapon:', weapon);
    return;
  }

  // If there's already an equipped weapon, it stays in inventory
  // Create a proper copy of the weapon to avoid reference issues
  gameState.equippedWeapon = {
    name: weapon.name,
    type: weapon.type,
    rarity: weapon.rarity,
    description: weapon.description,
    image: weapon.image,
    reference: weapon.reference,
    tags: weapon.tags,
    quantity: weapon.quantity
  };
  gameState.weaponLevel = 1; // Reset to level 1 when equipping new weapon

  console.log('🔫 Weapon equipped to gameState:', gameState.equippedWeapon);
  console.log('🔫 Weapon level set to:', gameState.weaponLevel);

  // Update UI
  updateInventory();
  updateEquipmentSlots();

  if (typeof createNotification === 'function') {
    createNotification(`Equipped ${weapon.name}`, '#ff9800', '⚔️');
  }

  console.log('✅ Weapon equipped successfully:', weapon.name);
}

function unequipWeapon() {
  if (!gameState.equippedWeapon) {
    return;
  }

  const weaponName = gameState.equippedWeapon.name;

  gameState.equippedWeapon = null;
  gameState.weaponLevel = 1;

  // Update UI
  updateInventory();
  updateEquipmentSlots();

  if (typeof createNotification === 'function') {
    createNotification(`Unequipped ${weaponName}`, '#888', '⚔️');
  }

  console.log('Unequipped weapon:', weaponName);
}

// ===== CURSES DISPLAY =====

function getCurseRemainingText(curse) {
  const curseName = curse.name.toLowerCase();

  // Curse of Weakness - shows "Next roll"
  if (curseName.includes('weakness')) {
    return 'Next roll';
  }

  // Curse of Failure - shows "On natural 1"
  if (curseName.includes('failure')) {
    return 'On natural 1';
  }

  // Curse of Vulnerability - shows remaining curse duplications
  if (curseName.includes('vulnerability')) {
    if (!gameState.vulnerabilityUses) gameState.vulnerabilityUses = {};
    const used = gameState.vulnerabilityUses[curse.name] || 0;
    const maxUses = typeof getCurseMaxUses === 'function' ? getCurseMaxUses(curse.power) : (curse.power === 'High' ? 3 : curse.power === 'Medium' ? 2 : 1);
    const remaining = maxUses - used;
    return `${remaining}/${maxUses} Curses Obtained left`;
  }

  // Curse of Shroud - shows remaining game selections
  if (curseName.includes('shroud')) {
    if (!gameState.shroudUses) gameState.shroudUses = {};
    const used = gameState.shroudUses[curse.name] || 0;
    const maxUses = typeof getCurseMaxUses === 'function' ? getCurseMaxUses(curse.power) : (curse.power === 'High' ? 3 : curse.power === 'Medium' ? 2 : 1);
    const remaining = maxUses - used;
    return `${remaining}/${maxUses} selections left`;
  }

  // Curse of Frugality - shows "Next purchase"
  if (curseName.includes('frugality')) {
    return 'Next purchase';
  }

  // Manual curses that track games beaten (Devotion, Greed, Impulse, etc.)
  const duration = curse.duration || '';
  if (duration.toLowerCase().includes('until') && duration.toLowerCase().includes('game')) {
    // Parse the required number of games from duration (e.g., "Until 2 Games Beaten" -> 2)
    const match = duration.match(/(\d+)\s+game/i);
    if (match) {
      const requiredGames = parseInt(match[1]);

      // Get current progress from tracker (use curse ID for accurate tracking of duplicates)
      if (!gameState.cursesTracker) gameState.cursesTracker = {};
      const trackerId = curse.id || curse.name; // Fallback to name for old saves
      const tracker = gameState.cursesTracker[trackerId] || { gamesBeaten: 0 };
      const currentGames = tracker.gamesBeaten || 0;
      return `${currentGames}/${requiredGames} games beaten`;
    }
  }

  // Default - show duration string
  return curse.duration;
}

function updateCursesDisplay() {
  const cursesList = document.getElementById('game-curses-list');
  if (!cursesList) return;

  // Get active curses from game state
  const activeCurses = gameState.activeCurses || [];

  if (activeCurses.length === 0) {
    cursesList.innerHTML = '<div class="empty-curses" style="color: #888; font-style: italic; padding: 10px; text-align: center;">No active curses</div>';
  } else {
    // Separate curses into restriction, manual, and automatic
    const restrictionCurses = activeCurses.filter(curse =>
      curse.name.toLowerCase().includes('blindness') ||
      curse.name.toLowerCase().includes('hubris')
    );
    const manualCurses = activeCurses.filter(curse =>
      curse.name.toLowerCase().includes('devotion') ||
      curse.name.toLowerCase().includes('greed') ||
      curse.name.toLowerCase().includes('impulse') ||
      curse.name.toLowerCase().includes('haste') ||
      curse.name.toLowerCase().includes('guilt')
    );
    const automaticCurses = activeCurses.filter(curse =>
      !restrictionCurses.includes(curse) && !manualCurses.includes(curse)
    );

    // Sort function: within same curse name, higher tier first (High > Medium > Low)
    const sortCursesByTier = (a, b) => {
      const powerOrder = { 'High': 3, 'Medium': 2, 'Low': 1 };
      const aBaseName = a.name.replace(/ (I|II|III)$/, '');
      const bBaseName = b.name.replace(/ (I|II|III)$/, '');

      // Same curse name - sort by tier
      if (aBaseName === bBaseName) {
        return (powerOrder[b.power] || 0) - (powerOrder[a.power] || 0);
      }
      // Different curse names - keep original order
      return 0;
    };

    // Sort each category by tier
    restrictionCurses.sort(sortCursesByTier);
    manualCurses.sort(sortCursesByTier);
    automaticCurses.sort(sortCursesByTier);

    // Display restriction (purple) first, then manual (orange), then automatic (red)
    const sortedCurses = [...restrictionCurses, ...manualCurses, ...automaticCurses];

    cursesList.innerHTML = sortedCurses.map((curse, idx) => {
      const remainingText = getCurseRemainingText(curse);
      const isRestriction = restrictionCurses.includes(curse);
      const isManual = manualCurses.includes(curse);

      // Different colors for restriction vs manual vs automatic curses
      const bgColor = isRestriction ? 'rgba(170, 102, 255, 0.1)' :
                      isManual ? 'rgba(255, 170, 68, 0.1)' :
                      'rgba(255, 102, 102, 0.1)';
      const borderColor = isRestriction ? '#aa66ff' :
                         isManual ? '#ffaa44' : '#ff6666';
      const titleColor = isRestriction ? '#bb99ff' :
                        isManual ? '#ffbb66' : '#ff9999';
      const descColor = isRestriction ? '#aa88cc' :
                       isManual ? '#ccaa88' : '#cc8888';
      const remainingColor = isRestriction ? '#9977aa' :
                            isManual ? '#aa9977' : '#aa7777';

      return `
        <div class="curse-display" style="
          background: ${bgColor};
          border: 1px solid ${borderColor};
          border-radius: 6px;
          padding: 8px;
          margin: 5px 0;
        ">
          <div style="color: ${titleColor}; font-weight: bold; font-size: 14px;">${curse.name}</div>
          <div style="color: ${descColor}; font-size: 12px; margin-top: 4px;">${curse.description}</div>
          <div style="color: ${remainingColor}; font-size: 11px; margin-top: 4px; font-style: italic;">Remaining: ${remainingText}</div>
        </div>
      `;
    }).join('');
  }
}

function updateVerificationCursesDisplay() {
  // Manual curses are now shown in the main curses display (orange-styled, above automatic curses)
  // This function is kept for backwards compatibility but no longer needed
  const verificationSection = document.getElementById('verification-curses');
  if (verificationSection) {
    verificationSection.style.display = 'none';
  }
}

// ===== GAME LISTS =====

function updateExcludedGamesList() {
  const excludedGamesListDiv = document.getElementById('excludedGamesList');
  excludedGamesListDiv.innerHTML = '';
  excludedGames.forEach((game, index) => {
    const gameDiv = document.createElement('div');
    gameDiv.className = 'excluded-game';
    gameDiv.innerHTML = `
      <strong>${game}</strong>
      <span class="remove-excluded-game" onclick="removeExcludedGame(${index})">×</span>
    `;
    excludedGamesListDiv.appendChild(gameDiv);
  });
}

function updateBeatenGamesList() {
  const beatenGamesListDiv = document.getElementById('beatenGamesList');
  beatenGamesListDiv.innerHTML = '';
  beatenGames.forEach((game, index) => {
    const gameDiv = document.createElement('div');
    gameDiv.className = 'beaten-game';
    gameDiv.innerHTML = `
      <strong>${game}</strong>
      <span class="remove-game" onclick="removeBeatenGame(${index})">×</span>
    `;
    beatenGamesListDiv.appendChild(gameDiv);
  });

  populateEscapeGameDropdown();
  document.getElementById('randomSelectForPhase2').disabled = beatenGames.length < 3;
}

function populateEscapeGameDropdown() {
  const selectGameForEscape = document.getElementById('selectGameForEscape');
  selectGameForEscape.innerHTML = '<option value="">-- Select a Game --</option>';
  beatenGames.forEach(game => {
    const option = document.createElement('option');
    option.value = game;
    option.textContent = game;
    selectGameForEscape.appendChild(option);
  });

  selectGameForEscape.disabled = beatenGames.length < 3;
  document.getElementById('addGameForEscape').disabled = beatenGames.length < 3;
}

function updateSelectedGamesDisplay() {
  const selectedGamesDiv = document.getElementById('selectedGames');
  selectedGamesDiv.innerHTML = '';
  selectedPhase2Games.forEach((game, index) => {
    const gameDiv = document.createElement('div');
    gameDiv.className = 'beaten-game';
    gameDiv.innerHTML = `
      <strong>${game}</strong>
      <span class="remove-selected-game" onclick="removeSelectedGame(${index})">×</span>
    `;
    selectedGamesDiv.appendChild(gameDiv);
  });

  if (selectedPhase2Games.length >= 3) {
    document.getElementById('selectGameForEscape').disabled = true;
    document.getElementById('addGameForEscape').disabled = true;
    document.getElementById('randomSelectForPhase2').disabled = true;
  }
}

// ===== PACT OF PUNISHMENT =====

function updateRoguePointsDisplay() {
  document.getElementById('rogue-points-display').textContent = `Rogue Points: ${roguePoints}`;
}

function updateConditionCounts() {
  document.getElementById('lessHealth-count').textContent = pactConditions.lessHealth;
  document.getElementById('moreGames-count').textContent = pactConditions.moreGames;
  document.getElementById('randomGame-count').textContent = pactConditions.randomGame;
  document.getElementById('challengeRun-count').textContent = pactConditions.challengeRun;
}

// ===== ENCOUNTER HISTORY =====

function updateEncounterHistory() {
  const historyDiv = document.getElementById('encounterHistory');
  historyDiv.innerHTML = '';

  encounterHistory.forEach((encounter, index) => {
    const encounterDiv = document.createElement('div');
    encounterDiv.className = 'encounter-history-item';

    if (encounter.type === 'event') {
      encounterDiv.innerHTML = `
        <strong>${encounter.name}</strong>
        <span class="remove-history-item" onclick="removeEncounterHistoryItem(${index})">×</span>
        <p>${encounter.option}</p>
        <small>${encounter.timestamp}</small>
      `;
    } else if (encounter.type === 'combat') {
      encounterDiv.innerHTML = `
        <strong>Combat: ${encounter.enemy}</strong>
        <span class="remove-history-item" onclick="removeEncounterHistoryItem(${index})">×</span>
        <p>${encounter.outcome}</p>
        <small>${encounter.timestamp}</small>
      `;
    }

    historyDiv.appendChild(encounterDiv);
  });
}

// ===== GAME STATS SIDEBAR =====

function updateGameStats() {
  // Update stats in the game view sidebar
  const statsHealth = document.getElementById('stats-health');
  const statsGold = document.getElementById('stats-gold');
  const statsStrength = document.getElementById('stats-strength');
  const statsDexterity = document.getElementById('stats-dexterity');
  const statsIntelligence = document.getElementById('stats-intelligence');
  const statsCharisma = document.getElementById('stats-charisma');
  const statsReroll = document.getElementById('stats-reroll');
  const statsDash = document.getElementById('stats-dash');
  const statsSkip = document.getElementById('stats-skip');
  const statsDiscovery = document.getElementById('stats-discovery');
  const statsFoV = document.getElementById('stats-fov');
  const statsLuck = document.getElementById('stats-luck');
  const statsItems = document.getElementById('stats-items');
  const statsGames = document.getElementById('stats-games');
  const statsSkippedGames = document.getElementById('stats-skipped');
  const statsDistance = document.getElementById('stats-distance');
  const statsDifficulty = document.getElementById('stats-difficulty');

  if (statsHealth) statsHealth.textContent = `${health}/${maxHealth}`;
  if (statsGold) statsGold.textContent = gold;

  // Update character info
  const characterIcon = document.getElementById('character-icon');
  const statsCharacterName = document.getElementById('stats-character-name');
  if (gameState && gameState.character && PLAYER_CHARACTERS[gameState.character]) {
    const character = PLAYER_CHARACTERS[gameState.character];
    if (characterIcon) characterIcon.src = character.fullImage || character.icon;
    if (statsCharacterName) statsCharacterName.textContent = character.name;
  }

  if (statsStrength) statsStrength.textContent = strength;
  if (statsDexterity) statsDexterity.textContent = dexterity;
  if (statsIntelligence) statsIntelligence.textContent = intelligence;
  if (statsCharisma) statsCharisma.textContent = charisma;
  if (statsReroll) statsReroll.textContent = reroll;
  if (statsDash) statsDash.textContent = dash;
  if (statsSkip) statsSkip.textContent = skip;
  if (statsDiscovery) statsDiscovery.textContent = discovery;

  // Check for Curse of Shroud (temporary FoV reduction) - handle stacking
  if (statsFoV) {
    const shroudCurses = gameState?.activeCurses?.filter(c => c.name.toLowerCase().includes('shroud')) || [];
    if (shroudCurses.length > 0) {
      const penalty = shroudCurses.length;
      const effectiveFoV = Math.max(1, fov - penalty);
      statsFoV.textContent = `${effectiveFoV} (${fov}-${penalty})`;
    } else {
      statsFoV.textContent = fov;
    }
  }

  if (statsLuck) statsLuck.textContent = luck;
  if (statsItems) statsItems.textContent = inventory.length;

  // Games Beaten = unique games finished in this run
  if (statsGames) {
    const finishedCount = gameState.finishedGames?.length || 0;
    statsGames.textContent = finishedCount;
  }

  // Games Skipped = games skipped in this run
  if (statsSkippedGames) {
    const skippedCount = gameState.skippedGames?.length || 0;
    statsSkippedGames.textContent = skippedCount;
  }

  // Distance = total games played (including replays)
  if (statsDistance) {
    statsDistance.textContent = gameState.visitedGames?.length || 0;
  }

  // Difficulty = unique games finished (matches difficulty in progress bar)
  if (statsDifficulty) {
    const difficulty = gameState.finishedGames?.length || 0;
    statsDifficulty.textContent = difficulty;
  }
}

// ===== SAVE/LOAD LIST =====

function updateSaveList() {
  const saveList = document.getElementById('save-list');
  if (!saveList) return;

  saveList.innerHTML = '';

  for (const [saveName, save] of Object.entries(gameSaves)) {
    const saveItem = document.createElement('div');
    saveItem.style.cssText = 'padding: 10px 15px; border-bottom: 1px solid #4a4440; display: flex; justify-content: space-between; align-items: center;';

    const characterName = PLAYER_CHARACTERS[save.character]?.name || 'Unknown';

    const infoDiv = document.createElement('div');
    infoDiv.style.cssText = 'cursor: pointer; flex: 1;';
    infoDiv.innerHTML = `
      <div style="font-weight: bold; color: #ffcc66;">${saveName}</div>
      <div style="font-size: 11px; color: #b8a890;">
        ${characterName} | Health: ${save.health}/${save.maxHealth} | Gold: ${save.gold} | Games: ${save.beatenGames?.length || 0}
      </div>
    `;

    infoDiv.onclick = () => {
      loadSavedGame(saveName);
      saveList.style.display = 'none';
    };

    infoDiv.onmouseenter = () => { saveItem.style.background = '#3a3430'; };
    infoDiv.onmouseleave = () => { saveItem.style.background = ''; };

    const deleteBtn = document.createElement('button');
    deleteBtn.textContent = '✕';
    deleteBtn.style.cssText = 'background: #ff6644; border: none; color: white; padding: 4px 8px; border-radius: 4px; cursor: pointer; font-weight: bold; margin-left: 10px;';
    deleteBtn.onclick = (e) => {
      e.stopPropagation();
      if (confirm(`Delete save "${saveName}"?`)) {
        delete gameSaves[saveName];
        GameStorage.save(STORAGE_KEYS.SAVED_GAMES, gameSaves);
        updateSaveList();
      }
    };

    saveItem.appendChild(infoDiv);
    saveItem.appendChild(deleteBtn);
    saveList.appendChild(saveItem);
  }

  const deleteBtn = document.createElement('div');
  deleteBtn.style.cssText = 'padding: 10px 15px; cursor: pointer; color: #ff6644; text-align: center; border-top: 1px solid #4a4440;';
  deleteBtn.textContent = 'Delete All Saves';
  deleteBtn.onclick = () => {
    if (confirm('Delete all saved games?')) {
      gameSaves = {};
      GameStorage.save(STORAGE_KEYS.SAVED_GAMES, gameSaves);
      updateSaveList();
    }
  };
  saveList.appendChild(deleteBtn);
}

// ===== ITEM TOOLTIPS =====

let itemTooltip;

function initItemTooltip() {
  if (!itemTooltip) {
    itemTooltip = document.getElementById('item-tooltip');
  }
  return itemTooltip;
}

function showItemTooltip(e, item) {
  const tooltip = initItemTooltip();
  if (!tooltip || !item) return;

  // Clear any pending hide timeout when showing
  if (itemTooltipHideTimeout) {
    clearTimeout(itemTooltipHideTimeout);
    itemTooltipHideTimeout = null;
  }

  // Get rarity color
  const rarityColors = {
    common: '#aaa',
    uncommon: '#4CAF50',
    rare: '#9b59b6',
    legendary: '#ff6b00'
  };
  const rarityColor = rarityColors[item.rarity] || '#ffffff';

  // Build tags HTML
  let tagsHTML = '';
  if (item.tags && item.tags.length > 0) {
    tagsHTML = `
      <div style="margin-top: 10px; padding-top: 8px; border-top: 1px solid rgba(255,255,255,0.2);">
        <div style="font-size: 11px; color: #888; margin-bottom: 4px;">Tags:</div>
        <div style="display: flex; flex-wrap: wrap; gap: 4px;">
          ${item.tags.map(tag => `
            <span style="
              font-size: 10px;
              padding: 2px 6px;
              background: rgba(100, 100, 100, 0.3);
              border: 1px solid rgba(150, 150, 150, 0.4);
              border-radius: 3px;
              color: #aaa;
            ">${tag}</span>
          `).join('')}
        </div>
      </div>
    `;
  }

  // Capitalize rarity
  const capitalizedRarity = item.rarity.charAt(0).toUpperCase() + item.rarity.slice(1);

  tooltip.innerHTML = `
    <h4 style="margin: 0 0 8px 0; color: ${rarityColor}; font-size: 18px;">${item.name}</h4>
    <div style="font-size: 12px; color: #b8a890; margin-bottom: 6px;">
      ${item.game ? `<div>From: ${item.game}</div>` : ''}
      <div>${capitalizedRarity} ${item.type}</div>
    </div>
    <div style="font-size: 13px; color: #e0d0b0; line-height: 1.4;">
      ${item.description}
    </div>
    ${tagsHTML}
  `;

  tooltip.style.opacity = 1;
  tooltip.style.display = 'block';
  moveItemTooltip(e);
}

function moveItemTooltip(e) {
  const tooltip = initItemTooltip();
  if (!tooltip) return;

  // Position tooltip to the right of the cursor, with boundary checks
  let left = e.clientX + 14;
  let top = e.clientY + 14;

  // Check if tooltip would go off screen on the right
  const tooltipWidth = 280; // Match CSS width
  const tooltipHeight = tooltip.offsetHeight || 200; // Estimate if not rendered

  if (left + tooltipWidth > window.innerWidth) {
    left = e.clientX - tooltipWidth - 14; // Position to the left instead
  }

  // Check if tooltip would go off screen on the bottom
  if (top + tooltipHeight > window.innerHeight) {
    top = window.innerHeight - tooltipHeight - 10;
  }

  tooltip.style.left = left + 'px';
  tooltip.style.top = top + 'px';
}

let itemTooltipHideTimeout = null;

function hideItemTooltip() {
  const tooltip = initItemTooltip();
  if (!tooltip) return;

  // Clear any pending hide timeout
  if (itemTooltipHideTimeout) {
    clearTimeout(itemTooltipHideTimeout);
  }

  tooltip.style.opacity = 0;
  itemTooltipHideTimeout = setTimeout(() => {
    tooltip.style.display = 'none';
    itemTooltipHideTimeout = null;
  }, 150);
}

// ===== EQUIPMENT SLOTS =====

function updateEquipmentSlots() {
  const weaponSlot = document.getElementById('weapon-slot');
  const amuletSlot = document.getElementById('amulet-slot');

  console.log('🔧 updateEquipmentSlots called', {
    weaponSlotExists: !!weaponSlot,
    amuletSlotExists: !!amuletSlot,
    equippedWeapon: gameState.equippedWeapon?.name,
    weaponLevel: gameState.weaponLevel
  });

  if (!weaponSlot || !amuletSlot) {
    console.warn('⚠️ Equipment slots not found in DOM');
    return;
  }

  // Update weapon slot
  if (gameState.equippedWeapon) {
    console.log('✅ Updating weapon slot with:', gameState.equippedWeapon);
    weaponSlot.classList.add('equipped');
    weaponSlot.innerHTML = `
      <img src="${gameState.equippedWeapon.image}" alt="${gameState.equippedWeapon.name}"
           onerror="this.style.display='none'">
      <button class="equipment-unequip-btn" onclick="unequipWeapon()">Unequip</button>
    `;

    // Add tooltip functionality
    weaponSlot.onmouseenter = (e) => {
      showWeaponTooltip(e, gameState.equippedWeapon);
    };
    weaponSlot.onmouseleave = () => {
      hideWeaponTooltip();
    };
  } else {
    weaponSlot.classList.remove('equipped');
    weaponSlot.innerHTML = '<div class="equipment-slot-empty">Weapon</div>';
    weaponSlot.onmouseenter = null;
    weaponSlot.onmouseleave = null;
  }

  // Amulet slot (for future use)
  amuletSlot.classList.remove('equipped');
  amuletSlot.innerHTML = '<div class="equipment-slot-empty">Amulet</div>';
}

function showWeaponTooltip(event, weapon) {
  const tooltip = document.getElementById('item-tooltip');
  if (!tooltip) return;

  const weaponLevel = gameState.weaponLevel || 1;
  const levelText = weaponLevel > 1 ? ` (Level ${weaponLevel})` : '';

  tooltip.innerHTML = `
    <div class="tooltip-header" style="color: ${getRarityColor(weapon.rarity)};">
      ${weapon.name}${levelText}
    </div>
    <div class="tooltip-type">${weapon.type} - ${weapon.rarity}</div>
    <div class="tooltip-description">${weapon.description}</div>
  `;

  const rect = event.currentTarget.getBoundingClientRect();
  tooltip.style.left = rect.right + 10 + 'px';
  tooltip.style.top = rect.top + 'px';
  tooltip.style.display = 'block';
}

function hideWeaponTooltip() {
  const tooltip = document.getElementById('item-tooltip');
  if (tooltip) {
    tooltip.style.display = 'none';
  }
}

function getRarityColor(rarity) {
  const rarityColors = {
    'Common': '#aaa',
    'Uncommon': '#4CAF50',
    'Rare': '#9b59b6',
    'Epic': '#e91e63',
    'Legendary': '#ff6b00'
  };
  return rarityColors[rarity] || '#aaa';
}

// Export functions to global scope for backwards compatibility
window.updateTopBar = updateTopBar;
window.updateHealthDisplay = updateHealthDisplay;
window.updateGoldDisplay = updateGoldDisplay;
window.updateInventory = updateInventory;
window.updateCursesDisplay = updateCursesDisplay;
window.updateVerificationCursesDisplay = updateVerificationCursesDisplay;
window.updateExcludedGamesList = updateExcludedGamesList;
window.updateBeatenGamesList = updateBeatenGamesList;
window.updateSelectedGamesDisplay = updateSelectedGamesDisplay;
window.updateRoguePointsDisplay = updateRoguePointsDisplay;
window.updateConditionCounts = updateConditionCounts;
window.updateEncounterHistory = updateEncounterHistory;
window.updateGameStats = updateGameStats;
window.updateSaveList = updateSaveList;
window.populateEscapeGameDropdown = populateEscapeGameDropdown;
window.updateEquipmentSlots = updateEquipmentSlots;
window.equipWeapon = equipWeapon;
window.unequipWeapon = unequipWeapon;
