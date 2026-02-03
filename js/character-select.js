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
    const diceHTML = character.dice.map(face => `
      <div style="
        background: rgba(255,255,255,0.1);
        border: 1px solid #666;
        border-radius: 4px;
        padding: 6px 10px;
        font-size: 12px;
        color: #fff;
      ">${face.raw || 'Blank'}</div>
    `).join('');

    // Build level-up stats HTML
    let levelUpHTML = '';
    if (character.levelUpStats) {
      const bonuses = Object.entries(character.levelUpStats)
        .filter(([_, value]) => value > 0)
        .map(([stat, value]) => `+${value} ${stat.charAt(0).toUpperCase() + stat.slice(1)}`)
        .join(', ');
      levelUpHTML = bonuses || 'None';
    }

    detailsHTML = `
      <img src="${character.fullImage}" alt="${character.name}" class="details-char-image">
      <h2 class="details-char-name">${character.name}</h2>
      <p class="details-char-game" style="color: #aaa; font-size: 13px; font-style: italic; margin: 2px 0 10px 0; text-align: center;">From: ${character.game || 'Unknown'}</p>
      <p class="details-char-description">${character.description}</p>

      <div class="details-stats-section">
        <h3>Combat Stats</h3>
        <div class="details-stats" style="display: flex; gap: 10px; justify-content: center;">
          <span class="stat-badge" style="background: rgba(255,200,0,0.2); border-color: #FFD700;">Energy: ${character.energy || 2}</span>
          <span class="stat-badge" style="background: rgba(138,43,226,0.2); border-color: #9C27B0;">Mana: ${character.mana || 0}</span>
        </div>
      </div>

      <div class="details-traits-section">
        <h3>Character Die (6 faces)</h3>
        <div style="display: flex; flex-wrap: wrap; gap: 6px; justify-content: center; margin-top: 10px;">
          ${diceHTML}
        </div>
      </div>

      ${character.levelUpCondition ? `
        <div style="margin-top: 15px; padding: 10px; background: rgba(255,215,0,0.1); border: 1px solid rgba(255,215,0,0.3); border-radius: 6px;">
          <div style="color: #FFD700; font-size: 12px; font-weight: bold; margin-bottom: 5px;">Level Up Condition:</div>
          <div style="color: #ccc; font-size: 13px;">${character.levelUpCondition}</div>
          <div style="color: #888; font-size: 11px; margin-top: 5px;">Rewards: ${levelUpHTML}</div>
        </div>
      ` : ''}
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
