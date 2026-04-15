/**
 * CHARACTER-SELECT.JS - Character Selection UI
 *
 * Responsibilities:
 * - Displaying character grid with icons
 * - Handling character selection
 * - Showing character details panel (stats, traits, description)
 * - Character card interactions
 *
 * Key Functions:
 * - populateIconCharacterView() - Populates character grid with icons
 * - showIconCharacterDetails(charKey) - Displays character info in side panel
 */

// ===== CHARACTER SELECTION FUNCTIONS =====

function populateIconCharacterView() {
  const characterKeys = Object.keys(PLAYER_CHARACTERS);
  const gridContainer = document.getElementById('icon-character-grid');

  if (!gridContainer) return;

  gridContainer.innerHTML = characterKeys.map(charKey => {
    const character = PLAYER_CHARACTERS[charKey];
    return `
      <div class="icon-char-card ${selectedCharacter === charKey ? 'selected' : ''}" data-char-key="${charKey}">
        <img src="${character.icon}" alt="${character.name}">
        <div class="icon-char-name">${character.name}</div>
      </div>
    `;
  }).join('');

  // Add event listeners for click
  gridContainer.querySelectorAll('.icon-char-card').forEach(card => {
    const charKey = card.dataset.charKey;

    // Click to select and show details
    card.addEventListener('click', () => {
      selectedCharacter = charKey;

      // Update visual selection
      gridContainer.querySelectorAll('.icon-char-card').forEach(c => c.classList.remove('selected'));
      card.classList.add('selected');

      // Show character details in the side panel
      showIconCharacterDetails(charKey);

      console.log('Character selected:', charKey);
    });
  });
}

function showIconCharacterDetails(charKey) {
  const character = PLAYER_CHARACTERS[charKey];
  const detailsPanel = document.getElementById('icon-character-details');
  const content = document.getElementById('icon-character-details-content');

  if (!detailsPanel || !content || !character) return;

  // Check if this is new dice-based format or old traits-based format
  const isNewFormat = character.dice && Array.isArray(character.dice);

  let detailsHTML = '';

  if (isNewFormat) {
    // New dice-based character format
    // Build dice HTML (enemy-style grid)
    const diceHTML = `
      <div style="display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; margin-top: 8px;">
        ${character.dice.map((face, idx) => {
          if (face.isBlank) {
            return `
              <div style="
                background: rgba(0,0,0,0.4);
                border: 1px solid #333;
                border-radius: 6px;
                padding: 8px;
                text-align: center;
                font-size: 11px;
                color: #666;
              ">
                <div style="font-weight: bold; color: #444;">Face ${idx + 1}</div>
                <div>Blank</div>
              </div>
            `;
          }
          return `
            <div style="
              background: rgba(76, 175, 80, 0.1);
              border: 1px solid rgba(76, 175, 80, 0.3);
              border-radius: 6px;
              padding: 8px;
              text-align: center;
              font-size: 11px;
              color: #ddd;
            ">
              <div style="font-weight: bold; color: #4CAF50; margin-bottom: 4px;">Face ${idx + 1}</div>
              <div>${face.raw || '—'}</div>
            </div>
          `;
        }).join('')}
      </div>
    `;

    // Build level-up bonuses list (check both formats)
    const levelUpBonuses = [];
    if (character.levelUpStats) {
      // New format with levelUpStats object
      Object.entries(character.levelUpStats).forEach(([stat, value]) => {
        if (value > 0) levelUpBonuses.push({ stat: stat.charAt(0).toUpperCase() + stat.slice(1), value });
      });
    } else {
      // Current format with stats at top level
      if (character.strength > 0) levelUpBonuses.push({ stat: 'Strength', value: character.strength });
      if (character.dexterity > 0) levelUpBonuses.push({ stat: 'Dexterity', value: character.dexterity });
      if (character.intelligence > 0) levelUpBonuses.push({ stat: 'Intelligence', value: character.intelligence });
      if (character.charisma > 0) levelUpBonuses.push({ stat: 'Charisma', value: character.charisma });
      if (character.luck > 0) levelUpBonuses.push({ stat: 'Luck', value: character.luck });
      if (character.reroll > 0) levelUpBonuses.push({ stat: 'Reroll', value: character.reroll });
      if (character.dash > 0) levelUpBonuses.push({ stat: 'Dash', value: character.dash });
      if (character.skip > 0) levelUpBonuses.push({ stat: 'Skip', value: character.skip });
      if (character.discovery > 0) levelUpBonuses.push({ stat: 'Discovery', value: character.discovery });
      if (character.fov > 0) levelUpBonuses.push({ stat: 'FoV', value: character.fov });
      if (character.random > 0) levelUpBonuses.push({ stat: 'Random', value: character.random });
    }
    const levelUpHTML = levelUpBonuses.length > 0
      ? levelUpBonuses.map(b => `<span style="color: #4CAF50; font-weight: bold;">+${b.value} ${b.stat}</span>`).join(', ')
      : '<span style="color: #888;">None</span>';

    // Get level up condition (check both field names)
    const levelUpCondition = character.levelUpCondition || character.levelUp || '';

    detailsHTML = `
      <img src="${character.fullImage}" alt="${character.name}" class="details-char-image">
      <h2 class="details-char-name">${character.name}</h2>
      <p class="details-char-game" style="color: #aaa; font-size: 13px; font-style: italic; margin: 2px 0 10px 0; text-align: center;">From: ${character.game || 'Unknown'}</p>
      <p class="details-char-description">${character.description}</p>

      <div class="details-stats-section">
        <h3>Starting Resources</h3>
        <div class="details-stats" style="display: flex; gap: 15px; justify-content: center;">
          <div style="background: rgba(255,204,0,0.15); border: 2px solid #FFD700; border-radius: 6px; padding: 8px 16px; text-align: center;">
            <div style="font-size: 10px; color: #FFD700; text-transform: uppercase;">Energy</div>
            <div style="font-size: 22px; font-weight: bold; color: #FFD700;">${character.energy || 2}</div>
          </div>
          <div style="background: rgba(102,179,255,0.15); border: 2px solid #66b3ff; border-radius: 6px; padding: 8px 16px; text-align: center;">
            <div style="font-size: 10px; color: #66b3ff; text-transform: uppercase;">Mana</div>
            <div style="font-size: 22px; font-weight: bold; color: #66b3ff;">${character.mana || 0}</div>
          </div>
        </div>
      </div>

      ${levelUpCondition ? `
        <div style="margin-top: 15px; padding: 12px; background: rgba(255,152,0,0.1); border: 1px solid rgba(255,152,0,0.3); border-radius: 6px;">
          <div style="color: #ff9800; font-size: 14px; font-weight: bold; margin-bottom: 8px;">⬆️ Level Up Condition</div>
          <div style="color: #ddd; font-size: 13px; margin-bottom: 8px;">${levelUpCondition}</div>
          <div style="color: #aaa; font-size: 12px;"><strong>Rewards:</strong> ${levelUpHTML}</div>
        </div>
      ` : ''}

      <div class="details-traits-section">
        <h3>Starting Deck</h3>
        ${(() => {
          const startingDeck = character.startingDeck || [];
          if (startingDeck.length === 0) return '<p style="color:#888;font-size:12px;">No starting deck</p>';
          const cardRows = startingDeck.map(entry => {
            const template = typeof CARDS_DATA !== 'undefined'
              ? CARDS_DATA.find(c => c.name === entry.cardName || c.name.toLowerCase() === entry.cardName.toLowerCase())
              : null;
            const color = template ? (template.rarity === 'Rare' ? '#9b59b6' : template.rarity === 'Uncommon' ? '#4CAF50' : '#888') : '#888';
            return `<div style="display:flex;align-items:center;gap:6px;background:rgba(0,0,0,0.3);border:1px solid ${color};border-radius:6px;padding:5px 8px;margin:3px 0;cursor:default;"
              onmouseenter="if(typeof showCardNameTooltip==='function') showCardNameTooltip('${entry.cardName.replace(/'/g,"\\'")}', event)"
              onmouseleave="if(typeof hideCardNameTooltip==='function') hideCardNameTooltip()">
              <span style="color:${color};font-weight:bold;font-size:15px;">x${entry.count}</span>
              <div>
                <div style="font-size:12px;color:white;font-weight:bold;">${entry.cardName}</div>
                ${template ? `<div style="font-size:10px;color:#aaa;">${template.type || ''} · Cost ${template.cost !== undefined ? template.cost : '?'}</div>` : ''}
              </div>
            </div>`;
          }).join('');
          return cardRows;
        })()}
        ${character.combatStart ? `
          <div style="margin-top:10px;padding:8px;background:rgba(255,152,0,0.1);border:1px solid rgba(255,152,0,0.4);border-radius:6px;">
            <div style="color:#ff9800;font-size:12px;font-weight:bold;margin-bottom:3px;">⚡ Combat Start</div>
            <div style="color:#ddd;font-size:12px;">${character.combatStart}</div>
          </div>
        ` : ''}
      </div>

      ${(() => {
        const startingItems = character.startingItems || [];
        if (startingItems.length === 0) return '';
        const itemRows = startingItems.map(itemName => {
          const itemData = typeof items !== 'undefined' ? items.find(i => i.name === itemName) : null;
          const rarityColor = itemData ? (itemData.rarity === 'Rare' ? '#9b59b6' : itemData.rarity === 'Uncommon' ? '#4CAF50' : '#888') : '#cc6600';
          return `<div style="display:flex;align-items:center;gap:6px;background:rgba(0,0,0,0.3);border:1px solid ${rarityColor};border-radius:6px;padding:5px 8px;margin:3px 0;">
            <span style="color:${rarityColor};font-weight:bold;font-size:16px;">★</span>
            <div>
              <div style="font-size:12px;color:white;font-weight:bold;">${itemName}</div>
              ${itemData ? `<div style="font-size:10px;color:#aaa;">${itemData.rarity || ''} · ${itemData.type || ''}</div>` : ''}
            </div>
          </div>`;
        }).join('');
        return `
          <div class="details-traits-section">
            <h3>Starting Item${startingItems.length > 1 ? 's' : ''}</h3>
            ${itemRows}
          </div>
        `;
      })()}
    `;
  } else {
    // Old traits-based format (fallback)
    const traitsHTML = (character.traits || []).map(traitId => {
      const trait = typeof TRAITS_DATA !== 'undefined' ? TRAITS_DATA[traitId] : null;
      if (!trait) return '';
      return `
        <div class="trait-box-detail">
          <span class="trait-icon">${trait.icon}</span>
          <div class="trait-info">
            <div class="trait-name">${trait.name}</div>
            <div class="trait-description">${trait.description}</div>
          </div>
        </div>
      `;
    }).join('');

    const statsHTML = character.startingStats ? Object.entries(character.startingStats)
      .filter(([_, value]) => value > 0)
      .map(([stat, value]) => `
        <span class="stat-badge">${stat.charAt(0).toUpperCase() + stat.slice(1)}: +${value}</span>
      `).join('') : '';

    detailsHTML = `
      <img src="${character.fullImage}" alt="${character.name}" class="details-char-image">
      <h2 class="details-char-name">${character.name}</h2>
      <p class="details-char-game" style="color: #aaa; font-size: 13px; font-style: italic; margin: 2px 0 10px 0; text-align: center;">From: ${character.game || 'Unknown'}</p>
      <p class="details-char-description">${character.description}</p>
      <div class="details-stats-section">
        <h3>Starting Stats</h3>
        <div class="details-stats">
          ${statsHTML || '<span class="stat-badge">No stat bonuses</span>'}
        </div>
      </div>
      <div class="details-traits-section">
        <h3>Traits</h3>
        ${traitsHTML || '<div>No traits</div>'}
      </div>
    `;
  }

  content.innerHTML = detailsHTML;
  detailsPanel.style.display = 'block';
}
