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

  // Build traits HTML
  const traitsHTML = character.traits.map(traitId => {
    const trait = TRAITS_DATA[traitId];
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

  // Build stats HTML
  const statsHTML = Object.entries(character.startingStats)
    .filter(([_, value]) => value > 0)
    .map(([stat, value]) => `
      <span class="stat-badge">${stat.charAt(0).toUpperCase() + stat.slice(1)}: +${value}</span>
    `).join('');

  content.innerHTML = `
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

  detailsPanel.style.display = 'block';
}
