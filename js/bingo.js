/**
 * BINGO.JS - Bingo System and Rewards
 *
 * Responsibilities:
 * - Bingo goal generation with difficulty tiers
 * - 3x3 Bingo grid rendering and interaction
 * - Line completion detection (rows, columns, diagonals)
 * - Progressive reward system with item choices
 * - Reward queue management for multiple bingos
 *
 * Key Functions:
 * - generateBingoGrid() - Creates 3x3 grid with easy/normal/hard goals
 * - toggleBingoCell(index) - Mark goals as complete
 * - checkForBingo() - Detect completed lines and grant rewards
 * - grantBingoReward(bingoCount) - Process reward with stat bonuses
 */

// ===== BINGO SYSTEM =====

const BINGO_GOALS = [
  // Easy goals (9)
  { goal: "Beat a boss with 1 Health left", difficulty: "easy" },
  { goal: "Defeat 15 Skeletons", difficulty: "easy" },
  { goal: "Defeat 15 Zombies", difficulty: "easy" },
  { goal: "Defeat an enemy with a ball", difficulty: "easy" },
  { goal: "Get drunk", difficulty: "easy" },
  { goal: "Pet a pet", difficulty: "easy" },
  { goal: "Trade health for resources", difficulty: "easy" },
  { goal: "Unlock a new Character", difficulty: "easy" },
  { goal: "Worship an altar", difficulty: "easy" },
  { goal: "Obtain a mushroom", difficulty: "easy" },

  // Normal goals (21)
  { goal: "Beat 3 Action Roguelikes", difficulty: "normal" },
  { goal: "Beat 3 Deckbuilder Roguelikes", difficulty: "normal" },
  { goal: "Beat 3 different roguelikes in one day", difficulty: "normal" },
  { goal: "Beat 3 Strategy Roguelikes", difficulty: "normal" },
  { goal: "Beat a run without meta progression", difficulty: "normal" },
  { goal: "Become a cannibal", difficulty: "normal" },
  { goal: "Complete a daily/weekly challenge run", difficulty: "normal" },
  { goal: "Deal damage equal to your block", difficulty: "normal" },
  { goal: "Defeat a boss without taking damage", difficulty: "normal" },
  { goal: "Defeat a magic boss with a gun", difficulty: "normal" },
  { goal: "Double your max health in a run", difficulty: "normal" },
  { goal: "Enchant an item to +5 or higher", difficulty: "normal" },
  { goal: "Get 10 achievements in 1 run", difficulty: "normal" },
  { goal: "Have a character reach \"level 30\"", difficulty: "normal" },
  { goal: "Have an enemy defeat 3 enemies", difficulty: "normal" },
  { goal: "Obtain 5 max tier items in one run", difficulty: "normal" },
  { goal: "Permanently remove 5 cards from your deck and win a run", difficulty: "normal" },
  { goal: "Ressurect yourself 3 times in one run and win", difficulty: "normal" },
  { goal: "Succesfully steal an item from a shop", difficulty: "normal" },
  { goal: "Tame an enemy", difficulty: "normal" },
  { goal: "Visit and beat the same game twice in one playthrough", difficulty: "normal" },

  // Hard goals (4)
  { goal: "Beat a run without moving", difficulty: "hard" },
  { goal: "Defeat a boss in 1 second or less/1 turn", difficulty: "hard" },
  { goal: "Beat a run without spending currency", difficulty: "hard" },
  { goal: "Beat a run without taking damage", difficulty: "hard" },
  { goal: "Beat the \"True\" ending of a game", difficulty: "hard" },
  { goal: "Get an achievement that only 10% of players or less have gotten ", difficulty: "hard" },

];

function generateBingoGrid() {
  if (bingoGoals.length === 0) {
    console.log('No bingo goals loaded');
    return;
  }

  // Separate goals by difficulty and shuffle to ensure randomness
  const easyGoals = [...bingoGoals.filter(g => g.difficulty === 'easy')];
  const normalGoals = [...bingoGoals.filter(g => g.difficulty === 'normal')];
  const hardGoals = [...bingoGoals.filter(g => g.difficulty === 'hard')];

  // Shuffle arrays
  const shuffleArray = (array) => {
    const shuffled = [...array];
    for (let i = shuffled.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
    }
    return shuffled;
  };

  const shuffledEasy = shuffleArray(easyGoals);
  const shuffledNormal = shuffleArray(normalGoals);
  const shuffledHard = shuffleArray(hardGoals);

  // Reset grid
  bingoGrid = Array(9).fill(null);
  bingoCompleted = Array(9).fill(false);

  // Track used goals to prevent duplicates
  const usedGoals = new Set();

  // Place 1 easy goal in center (position 4)
  if (shuffledEasy.length > 0) {
    const easyGoal = shuffledEasy[0];
    bingoGrid[4] = { ...easyGoal };
    usedGoals.add(easyGoal.goal);
  } else if (shuffledNormal.length > 0) {
    const normalGoal = shuffledNormal[0];
    bingoGrid[4] = { ...normalGoal };
    usedGoals.add(normalGoal.goal);
  }

  // Place 2 hard goals in random positions (not center)
  const availablePositions = [0, 1, 2, 3, 5, 6, 7, 8];
  let hardGoalIndex = 0;
  for (let i = 0; i < 2 && hardGoalIndex < shuffledHard.length; i++) {
    // Find next unused hard goal
    while (hardGoalIndex < shuffledHard.length && usedGoals.has(shuffledHard[hardGoalIndex].goal)) {
      hardGoalIndex++;
    }

    if (hardGoalIndex < shuffledHard.length) {
      const posIndex = Math.floor(Math.random() * availablePositions.length);
      const position = availablePositions.splice(posIndex, 1)[0];
      const hardGoal = shuffledHard[hardGoalIndex];
      bingoGrid[position] = { ...hardGoal };
      usedGoals.add(hardGoal.goal);
      hardGoalIndex++;
    }
  }

  // Fill remaining positions with normal goals
  let normalGoalIndex = 0;
  availablePositions.forEach(pos => {
    // Find next unused normal goal
    while (normalGoalIndex < shuffledNormal.length && usedGoals.has(shuffledNormal[normalGoalIndex].goal)) {
      normalGoalIndex++;
    }

    if (normalGoalIndex < shuffledNormal.length) {
      const normalGoal = shuffledNormal[normalGoalIndex];
      bingoGrid[pos] = { ...normalGoal };
      usedGoals.add(normalGoal.goal);
      normalGoalIndex++;
    }
  });

  renderBingoGrid();
}

function renderBingoGrid() {
  const gridContainer = document.getElementById('bingo-grid');
  if (!gridContainer) return;

  gridContainer.innerHTML = '';

  bingoGrid.forEach((goal, index) => {
    const cell = document.createElement('div');
    cell.className = `bingo-cell ${goal ? goal.difficulty : 'normal'}`;
    if (bingoCompleted[index]) {
      cell.classList.add('completed');
    }

    const badge = document.createElement('div');
    badge.className = `bingo-difficulty-badge ${goal ? goal.difficulty : 'normal'}`;

    const text = document.createElement('div');
    text.className = 'bingo-cell-text';
    text.textContent = goal ? goal.goal : 'Empty';

    cell.appendChild(badge);
    cell.appendChild(text);

    cell.addEventListener('click', () => toggleBingoCell(index));

    gridContainer.appendChild(cell);
  });
}

function toggleBingoCell(index) {
  bingoCompleted[index] = !bingoCompleted[index];
  renderBingoGrid();
  checkForBingo();
}

// Reward queue for handling multiple bingos
let bingoRewardQueue = [];
let processingBingoReward = false;
let usedBingoItems = []; // Track items shown in current batch to avoid duplicates

function checkForBingo() {
  const lines = [
    // Rows
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    // Columns
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    // Diagonals
    [0, 4, 8],
    [2, 4, 6]
  ];

  let newBingos = 0;
  lines.forEach(line => {
    if (line.every(index => bingoCompleted[index])) {
      newBingos++;
    }
  });

  if (newBingos > completedBingos) {
    const bingosToGrant = newBingos - completedBingos;
    const oldBingosCount = completedBingos;

    // Update count first
    completedBingos = newBingos;

    // Queue rewards for each new bingo (using sequential reward types)
    usedBingoItems = []; // Reset used items for this batch
    for (let i = 0; i < bingosToGrant; i++) {
      bingoRewardQueue.push(oldBingosCount + i + 1);
    }

    // Start processing the queue
    processNextBingoReward();

    // Update display
    updateBingoStatus();

    // Show celebration
    const bingoGridEl = document.getElementById('bingo-grid');
    if (bingoGridEl) {
      bingoGridEl.classList.add('bingo-complete-animation');
      setTimeout(() => {
        bingoGridEl.classList.remove('bingo-complete-animation');
      }, 1500);
    }
  }

  updateBingoStatus();
}

function processNextBingoReward() {
  if (processingBingoReward) {
    return;
  }

  if (bingoRewardQueue.length === 0) {
    // All rewards processed, clear used items for next batch
    usedBingoItems = [];
    return;
  }

  processingBingoReward = true;
  const bingoCount = bingoRewardQueue.shift();
  grantBingoReward(bingoCount);
}

function updateBingoStatus() {
  const bingoCountEl = document.getElementById('bingo-count');
  if (bingoCountEl) {
    bingoCountEl.textContent = `${completedBingos} Bingo${completedBingos !== 1 ? 's' : ''} Complete`;
  }
}

function grantBingoReward(bingoCount) {
  // Rewards are given in order based on bingoCount parameter (1-8, then cycle)
  const rewardType = ((bingoCount - 1) % 8) + 1;

  // All rewards give +1 to all combat stats
  strength++;
  dexterity++;
  intelligence++;
  charisma++;
  updateTopBar();

  let bonusText = '+1 to All Combat Stats';

  // Apply specific reward bonuses
  switch(rewardType) {
    case 1:
      // Common items
      giveRandomItems('common', bingoCount, bonusText);
      break;
    case 2:
      // Common items
      giveRandomItems('common', bingoCount, bonusText);
      break;
    case 3:
      // Common items + 2 Reroll
      reroll += 2;
      bingoReroll += 2;
      bonusText += ', +2 Reroll';
      giveRandomItems('common', bingoCount, bonusText);
      break;
    case 4:
      // Uncommon items
      giveRandomItems('uncommon', bingoCount, bonusText);
      break;
    case 5:
      // Uncommon items + 1 Skip
      skip += 1;
      bingoSkip += 1;
      bonusText += ', +1 Skip';
      giveRandomItems('uncommon', bingoCount, bonusText);
      break;
    case 6:
      // Rare items
      giveRandomItems('rare', bingoCount, bonusText);
      break;
    case 7:
      // Rare items + FoV & Discovery
      fov += 1;
      discovery += 1;
      bingoFoV += 1;
      bingoDiscovery += 1;
      bonusText += ', +1 FoV & Discovery';
      giveRandomItems('rare', bingoCount, bonusText);
      break;
    case 8:
      // Rare items + Dash
      dash += 1;
      bingoDash += 1;
      bonusText += ', +1 Dash';
      giveRandomItems('rare', bingoCount, bonusText);
      break;
  }
}

function giveRandomItems(rarity, bingoCount = 1, bonusText = '') {
  // Filter out items already selected in this batch of bingo rewards
  // Case-insensitive rarity comparison
  const rarityItems = items.filter(item =>
    item.rarity && item.rarity.toLowerCase() === rarity.toLowerCase() && !usedBingoItems.includes(item.name)
  );

  if (rarityItems.length === 0) {
    console.log(`No ${rarity} items available`);
    alert(`No ${rarity} items available!`);
    processingBingoReward = false;
    processNextBingoReward();
    return;
  }

  // Number of choices = 2 + discovery (affected by discovery stat)
  const numChoices = Math.min(2 + discovery, rarityItems.length);
  const choices = [];

  // Generate random item choices (all from the same rarity, excluding already selected items)
  for (let i = 0; i < numChoices && i < rarityItems.length; i++) {
    let randomItem;
    do {
      randomItem = rarityItems[Math.floor(Math.random() * rarityItems.length)];
    } while (choices.find(c => c.name === randomItem.name));
    choices.push(randomItem);
  }

  const rarityColor = rarity === 'common' ? '#aaa' : rarity === 'uncommon' ? '#4CAF50' : '#9b59b6';

  // Show queue info if there are more rewards pending
  const queueInfo = bingoRewardQueue.length > 0
    ? `<p style="text-align: center; color: #ffaa00; font-size: 14px; margin-top: 0;">${bingoRewardQueue.length} more reward${bingoRewardQueue.length > 1 ? 's' : ''} pending...</p>`
    : '';

  let itemsHTML = '<div style="display: flex; flex-wrap: wrap; gap: 20px; margin-top: 20px; justify-content: center;">';

  choices.forEach((item, index) => {
    itemsHTML += `
      <div class="bingo-item-choice-card" data-index="${index}" style="
        flex: 1;
        max-width: 250px;
        padding: 20px;
        background: #2d2d2d;
        border: 3px solid ${rarityColor};
        border-radius: 12px;
        cursor: pointer;
        transition: all 0.3s;
        text-align: center;
      ">
        ${item.image ? `<img src="${item.image}" style="width: 100px; height: 100px; object-fit: contain; image-rendering: pixelated; margin: 0 auto 15px; display: block; border-radius: 8px; border: 2px solid ${rarityColor};" alt="${item.name}" onerror="this.style.display='none';">` : ''}
        <div style="font-size: 20px; font-weight: bold; margin-bottom: 10px;">${item.name}</div>
        <div style="color: ${rarityColor}; font-size: 14px; margin-bottom: 15px;">${item.rarity}</div>
        <div style="color: #ccc; font-size: 14px; line-height: 1.5;">${item.description}</div>
        <div style="color: #888; font-size: 12px; margin-top: 10px; font-style: italic;">${item.type}</div>
      </div>
    `;
  });

  itemsHTML += '</div>';
  itemsHTML += '<p style="text-align: center; color: #888; margin-top: 20px; font-size: 14px;">Click an item to choose it</p>';

  createGameModal(`
    <div>
      <h2 style="color: gold; margin-top: 0; text-align: center;">🎯 Bingo #${bingoCount} Complete!</h2>
      ${queueInfo}
      <p style="text-align: center; color: #4CAF50; font-weight: bold; margin: 10px 0;">${bonusText}</p>
      <p style="text-align: center; color: #aaa;">Select one ${rarity} item to add to your inventory</p>
      ${itemsHTML}
    </div>
  `);

  document.querySelectorAll('.bingo-item-choice-card').forEach(card => {
    card.onmouseenter = (e) => {
      e.currentTarget.style.transform = 'translateY(-5px) scale(1.05)';
      e.currentTarget.style.boxShadow = '0 10px 30px rgba(255, 215, 0, 0.4)';
    };
    card.onmouseleave = (e) => {
      e.currentTarget.style.transform = '';
      e.currentTarget.style.boxShadow = '';
    };
    card.onclick = (e) => {
      const itemIndex = parseInt(e.currentTarget.dataset.index);
      const item = choices[itemIndex];

      acquireItem(item);
      closeGameModal();

      if (typeof updateInventory === 'function') {
        updateInventory();
      }

      // Track this selected item to avoid showing it again in the same batch
      usedBingoItems.push(item.name);

      // Mark this reward as processed and show next one if queued
      processingBingoReward = false;
      processNextBingoReward();
    };
  });
}

function showBingoRewards() {
  const rewardsModal = document.getElementById('rewards-modal');
  if (rewardsModal) {
    rewardsModal.classList.add('show');
  }
}

function toggleBingo() {
  const container = document.getElementById('bingo-container');
  const button = document.getElementById('bingo-toggle');
  const goalsButton = document.getElementById('toggle-bingo-btn');

  if (!container) return;

  if (container.classList.contains('hidden')) {
    container.classList.remove('hidden');
    if (button) button.textContent = 'Hide';
    if (goalsButton) goalsButton.textContent = 'Hide Bingo';
  } else {
    container.classList.add('hidden');
    if (button) button.textContent = 'Show';
    if (goalsButton) goalsButton.textContent = 'Show Bingo';
  }
}
