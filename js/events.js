// ===== EVENTS.JS - Random Events, Shops, and Encounters =====
//
// This module handles:
// - Random event selection
// - Event option detection and handling
// - Shop mechanics
// - Event outcomes and consequences

// ===== EVENT DETECTION =====

function detectOptionType(optionText) {
  const text = optionText.toLowerCase();
  if (text.includes('attack') || text.includes('fight')) return 'attack';
  if (text.includes('look') || text.includes('search') || text.includes('explore')) return 'explore';
  if (text.includes('talk') || text.includes('ask') || text.includes('speak')) return 'talk';
  if (text.includes('use') || text.includes('item')) return 'item';
  if (text.includes('buy') || text.includes('purchase')) return 'shop';
  if (text.includes('pray') || text.includes('bless')) return 'shrine';
  return 'default';
}

// ===== EVENT OUTCOME GENERATION =====

function getOptionOutcomeText(option) {
  const text = option.toLowerCase();

  // Combat options
  if (text.includes('attack') || text.includes('fight') || text.includes('smash')) {
    return "The enemy recoils from your strike!";
  }

  // Talk/Charisma options
  if (text.includes('talk') || text.includes('ask') || text.includes('persuade')) {
    return "The conversation yields useful information.";
  }

  // Search/Explore options
  if (text.includes('search') || text.includes('look') || text.includes('explore')) {
    return "Your careful investigation reveals hidden secrets.";
  }

  // Item usage
  if (text.includes('use') || text.includes('consume')) {
    return "The item's magic surges through you.";
  }

  // Shop/Purchase
  if (text.includes('buy') || text.includes('purchase')) {
    return "A fair trade is made.";
  }

  // Prayer/Shrine
  if (text.includes('pray') || text.includes('offer')) {
    return "Your devotion is recognized.";
  }

  // Disarm/Dexterity
  if (text.includes('disarm') || text.includes('carefully')) {
    return "Your nimble fingers make quick work of the mechanism.";
  }

  // Decline/Leave
  if (text.includes('decline') || text.includes('leave') || text.includes('walk away')) {
    return "Sometimes discretion is the better part of valor.";
  }

  // Default
  return "Your actions have consequences...";
}

// ===== EVENT OPTION HANDLING =====

function selectEncounterOption(eventIndex, optionIndex) {
  const event = events[eventIndex];
  const option = event.options[optionIndex];

  // Visual feedback
  const optionElement = document.querySelectorAll('.event-option')[optionIndex];
  if (optionElement) {
    optionElement.style.backgroundColor = '#d0d0d0';
    setTimeout(() => {
      optionElement.style.backgroundColor = '';
    }, 200);
  }

  // Parse option for rewards/consequences
  const goldMatch = option.match(/(\d+) gold/i);
  if (goldMatch) {
    const amount = parseInt(goldMatch[1]);
    const delta = option.toLowerCase().includes('lose') ? -amount : amount;
    StateMutator.modifyGold(delta);
  }

  // Health changes
  const healthMatch = option.match(/([+-]?\d+) health/i);
  if (healthMatch) {
    let amount = parseInt(healthMatch[1]);
    if (amount > 0 || option.toLowerCase().includes('heal')) {
      StateMutator.modifyHealth(Math.abs(amount));
    } else {
      // Apply damage reduction from items (like Garlic)
      let damage = Math.abs(amount);
      if (typeof calculateDamageReduction === 'function') {
        damage = calculateDamageReduction(damage);
      }
      StateMutator.modifyHealth(-damage);
    }
  }

  // Max health changes
  if (option.toLowerCase().includes('max health')) {
    const maxHealthMatch = option.match(/([+-]?\d+) max health/i);
    if (maxHealthMatch) {
      const amount = parseInt(maxHealthMatch[1]);
      StateMutator.modifyMaxHealth(amount);
    }
  }

  // Stat bonuses
  const statMatch = option.match(/(strength|dexterity|intelligence|charisma)/i);
  if (statMatch && option.match(/\+\d+/)) {
    const stat = statMatch[1];
    const bonus = parseInt(option.match(/\+(\d+)/)[1]);
    applyStatBonus(stat, bonus);
  }

  // Record in history
  encounterHistory.push({
    type: 'event',
    name: event.name,
    option: option,
    timestamp: new Date().toLocaleString()
  });

  updateEncounterHistory();

  // Display outcome
  document.getElementById('eventResult').innerHTML = `
    <h4>${event.name}</h4>
    <p>You chose: <strong>${option}</strong></p>
    <p>${getOptionOutcomeText(option)}</p>
  `;
}

// ===== SHOP MECHANICS =====

function displayShop() {
  const shopItems = items.filter(item => {
    // Shop has a mix of rarities with appropriate prices
    // Exclude N/A rarity items (boons)
    return item.rarity !== 'N/A';
  });

  const shopSelection = [];
  const numItems = 3;

  for (let i = 0; i < numItems; i++) {
    // Use luck-based rarity selection
    const targetRarity = selectRandomRarity();

    const rarityItems = shopItems.filter(item => item.rarity === targetRarity && item.rarity !== 'N/A');
    if (rarityItems.length > 0) {
      const randomItem = rarityItems[Math.floor(Math.random() * rarityItems.length)];

      // Price based on rarity
      let price;
      switch(targetRarity) {
        case 'common': price = 10; break;
        case 'uncommon': price = 25; break;
        case 'rare': price = 50; break;
        default: price = 10;
      }

      shopSelection.push({ ...randomItem, price });
    }
  }

  return shopSelection;
}

function purchaseItem(item, price) {
  if (gold >= price) {
    StateMutator.modifyGold(-price);
    acquireItem(item);
    return true;
  }
  return false;
}

// Export to global scope
window.detectOptionType = detectOptionType;
window.getOptionOutcomeText = getOptionOutcomeText;
window.selectEncounterOption = selectEncounterOption;
window.displayShop = displayShop;
window.purchaseItem = purchaseItem;
