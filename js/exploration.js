/**
 * EXPLORATION.JS - Exploration Phase Game Mechanics
 *
 * Responsibilities:
 * - Spawning game choices during exploration
 * - Advancing from game to game
 * - Managing the "Finished" button flow
 * - Managing ability buttons (Dash, Reroll, Skip)
 * - Node clearing and arrow management for choices
 *
 * Key Functions:
 * - spawnChoices() - Spawns next game choices based on connections
 * - advance(game, x, y, encounterType) - Advances to next game
 * - showFinish(node, isAmuletGame) - Shows Finished button after completing a game
 * - clearChoices() - Removes choice nodes and redraws path
 * - clearAllArrows() - Clears all CSS arrows (for screen transitions)
 */

// ===== CHOICE MANAGEMENT =====

function clearChoices() {
  // Remove choice nodes
  document.querySelectorAll('.node.choice').forEach(n => n.remove());

  // Clear ALL CSS arrows including background connection arrows
  // Background arrows will be redrawn when needed during choice selection
  document.querySelectorAll('.css-arrow').forEach(arrow => arrow.remove());

  // Redraw past path
  const pastNodes = document.querySelectorAll('.node.past');
  for (let i = 0; i < pastNodes.length - 1; i++) {
    drawPastLine(pastNodes[i], pastNodes[i + 1]);
  }

  // Draw line from last past node to current
  const currentNode = document.querySelector('.node.current');
  if (pastNodes.length > 0 && currentNode) {
    drawPastLine(pastNodes[pastNodes.length - 1], currentNode);
  }
}

function clearAllArrows() {
  // Clear ALL CSS arrows including background connection arrows
  // Used when exiting the dungeon screen to prevent arrows from showing on other screens
  document.querySelectorAll('.css-arrow').forEach(arrow => arrow.remove());
}

// ===== SPAWN CHOICES =====

function spawnChoices() {
  clearChoices();

  // Set phase to selection
  gameState.phase = 'selection';

  // Update inventory to refresh usable item buttons
  if (typeof updateInventory === 'function') {
    updateInventory();
  }

  // Get all connected games
  const allConnections = getGameConnections(gameState.currentGame);

  // Add portal games if current game has a portal
  let gamesToChooseFrom = [...allConnections];
  if (typeof hasGameStatus === 'function' && hasGameStatus(gameState.currentGame, 'portal')) {
    // Get all other portal games
    const portalGames = typeof getGamesWithStatus === 'function'
      ? getGamesWithStatus('portal').filter(g => g !== gameState.currentGame)
      : [];

    if (portalGames.length > 0) {
      gamesToChooseFrom = [...gamesToChooseFrom, ...portalGames];
    }
  }

  // Separate stinky and non-stinky games
  const nonStinkyGames = gamesToChooseFrom.filter(g =>
    typeof hasGameStatus !== 'function' || !hasGameStatus(g, 'stinky')
  );
  const stinkyGames = gamesToChooseFrom.filter(g =>
    typeof hasGameStatus === 'function' && hasGameStatus(g, 'stinky')
  );

  // Shuffle non-stinky games
  const shuffledNonStinky = shuffleArray(nonStinkyGames);

  // Shuffle stinky games
  const shuffledStinky = shuffleArray(stinkyGames);

  // Combine: non-stinky first, then stinky (deprioritized)
  const shuffled = [...shuffledNonStinky, ...shuffledStinky];

  let baseFov = fov + 3; // Base 3 + fov stat

  // Check for Curse of Shroud (lower FoV) - handle stacking
  const shroudCurses = CurseManager.findByType('shroud');
  if (shroudCurses.length > 0) {
    // Apply FoV reduction for each shroud curse
    shroudCurses.forEach(shroudCurse => {
      baseFov = Math.max(1, baseFov - 1);
    });

    // Process the first shroud curse for tracking and removal
    const shroudCurse = shroudCurses[0];

    // Track how many times we've used this curse
    if (!gameState.shroudUses) {
      gameState.shroudUses = {};
    }
    if (!gameState.shroudUses[shroudCurse.name]) {
      gameState.shroudUses[shroudCurse.name] = 0;
    }

    // Determine max uses based on power
    const maxUses = typeof getCurseMaxUses === 'function' ? getCurseMaxUses(shroudCurse.power) : (shroudCurse.power === 'High' ? 3 : shroudCurse.power === 'Medium' ? 2 : 1);

    // Increment uses
    gameState.shroudUses[shroudCurse.name]++;

    // Remove this specific curse instance if we've used all charges
    if (gameState.shroudUses[shroudCurse.name] >= maxUses) {
      CurseManager.consume(shroudCurse);
      delete gameState.shroudUses[shroudCurse.name];
      if (typeof updateActiveCursesList === 'function') {
        updateActiveCursesList();
      }
    }
  }

  const numChoices = Math.max(1, baseFov); // Use fov stat, default to 3
  const opts = shuffled.slice(0, Math.min(numChoices, shuffled.length));

  // Apply pending boon statuses to random games in this choice set
  if (gameState.pendingLocationStatuses && gameState.pendingLocationStatuses.length > 0) {

    // Apply each pending status to a random game in the choice set
    gameState.pendingLocationStatuses.forEach(statusName => {
      if (opts.length > 0) {
        const randomIndex = Math.floor(Math.random() * opts.length);
        const targetGame = opts[randomIndex];

        // Add the status to the game
        if (typeof addGameStatus === 'function') {
          addGameStatus(targetGame, statusName.toLowerCase());
        }
      }
    });

    // Clear pending statuses after applying
    gameState.pendingLocationStatuses = [];
  }

  // Store current choices so the map can highlight them
  gameState.currentChoices = [...opts];

  // Dynamic positioning based on number of choices
  // Node max width = 220px + 56px padding + 6px border = ~282px
  // Use minimum spacing of 300px to ensure no overlap even with long names
  const nodeSpacing = 300;
  const maxPerRow = 4; // Maximum nodes per row
  const rowSpacing = 150; // Vertical spacing between rows
  const baseY = gameState.currentY + 200;

  // Calculate rows and positioning
  const numRows = Math.ceil(opts.length / maxPerRow);
  const currentNode = document.querySelector('.node.current');

  opts.forEach((g, i) => {
    const row = Math.floor(i / maxPerRow);
    const posInRow = i % maxPerRow;
    const nodesInThisRow = Math.min(maxPerRow, opts.length - row * maxPerRow);

    // Center each row horizontally
    const rowWidth = (nodesInThisRow - 1) * nodeSpacing;
    const startX = 450 - rowWidth / 2;

    const nx = startX + posInRow * nodeSpacing;
    const ny = baseY + row * rowSpacing;

    // Apply Isaac location modifiers (10% chance for Holy/Devilish/Stinky)
    if (gameState?.location && typeof applyIsaacModifiers === 'function') {
      applyIsaacModifiers(g, gameState.location);
    }

    // Get encounter type from gameState (randomly assigned per run)
    let encounterType, encounterIcon, encounterColor;

    // Find the game object
    const game = games.find(game => game.name === g);

    // Get encounter type from current run's assignments
    encounterType = gameState.encounterTypes?.[g];

    if (game && encounterType) {
      // Set icon and color based on encounter type
      if (encounterType === 'combat') {
        encounterIcon = '!';
        // Get game type for color
        switch(game.type.toLowerCase()) {
          case 'action': encounterColor = 'red'; break;
          case 'deckbuilding': encounterColor = 'purple'; break;
          case 'strategy': encounterColor = 'blue'; break;
          default: encounterColor = 'green'; break;
        }
      } else if (encounterType === 'event') {
        encounterIcon = '?';
        encounterColor = 'purple';
      } else if (encounterType === 'shop') {
        encounterIcon = '$';
        encounterColor = 'gold';
      }
    } else {
      // Fallback to random if encounterType not found (shouldn't happen)
      console.warn(`No encounterType found for game: ${g}, using fallback random generation`);
      const encounterRoll = Math.random() * 100;
      if (encounterRoll < 75) {
        encounterType = 'combat';
        encounterIcon = '!';
        encounterColor = 'red';
      } else if (encounterRoll < 90) {
        encounterType = 'event';
        encounterIcon = '?';
        encounterColor = 'purple';
      } else {
        encounterType = 'shop';
        encounterIcon = '$';
        encounterColor = 'gold';
      }
    }

    const n = addNode(g, 'choice', nx, ny);

    // Revisit indicator: badge shown when the player has already beaten this game
    if (gameState.finishedGames && gameState.finishedGames.includes(g)) {
      const revisitBadge = document.createElement('span');
      revisitBadge.title = 'Already beaten — revisiting grants +1 Dash';
      revisitBadge.textContent = '💨';
      revisitBadge.style.cssText = [
        'position:absolute', 'top:-12px', 'left:-12px',
        'width:26px', 'height:26px',
        'background:#2980b9', 'color:#fff',
        'border-radius:50%',
        'display:flex', 'align-items:center', 'justify-content:center',
        'font-size:14px',
        'border:2px solid #000',
        'box-shadow:0 2px 8px rgba(0,0,0,0.4)',
        'cursor:default',
      ].join(';');
      n.appendChild(revisitBadge);
    }

    // Check if this is the amulet game
    const isAmuletGame = (g === gameState.amuletGame.name);

    // Override encounter type if it's the amulet game
    if (isAmuletGame) {
      encounterType = 'amulet';
      encounterIcon = '🏺';
      encounterColor = 'gold';
    }

    // Add encounter icon to the node
    const icon = document.createElement('span');
    icon.textContent = encounterIcon;
    icon.style.cssText = `
      position: absolute;
      top: -12px;
      right: -12px;
      width: 26px;
      height: 26px;
      background: ${encounterColor};
      color: ${encounterColor === 'gold' ? '#000' : '#fff'};
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 16px;
      font-weight: bold;
      border: 2px solid #000;
      box-shadow: 0 2px 8px rgba(0,0,0,0.4);
    `;
    n.appendChild(icon);

    // Store encounter type on the node
    n.dataset.encounterType = encounterType;

    n.onclick = () => advance(g, nx, ny, encounterType);
  });

  // Draw arrows after all nodes are added and browser has laid them out
  requestAnimationFrame(() => {

    // Draw background connection arrows (gray) for all game connections
    drawAllGameConnections();

    // Draw choice arrows
    const currentNode = document.querySelector('.node.current');
    const choiceNodes = document.querySelectorAll('.node.choice');

    if (currentNode) {
      choiceNodes.forEach(choiceNode => {
        drawArrowLine(currentNode, choiceNode);
      });
    } else {
      console.warn('No current node found to draw arrows from!');
    }
  });

  // Add Dash and Reroll buttons during choice selection
  addDashRerollButtons();
}

// ===== ABILITY BUTTONS =====

// Add Dash and Reroll buttons attached to current game node during choice selection
function addDashRerollButtons() {
  // Remove old buttons if they exist
  const oldDash = document.querySelector('.node-dash-btn');
  const oldReroll = document.querySelector('.node-reroll-btn');
  if (oldDash) oldDash.remove();
  if (oldReroll) oldReroll.remove();

  // Find the current game node
  const currentNode = document.querySelector('.node.current');
  if (!currentNode) return;

  // Add Dash button (left side of current node) - always shown, grayed out if dash === 0
  if (true) {
    const dashBtn = document.createElement('button');
    dashBtn.className = 'node-dash-btn';
    dashBtn.textContent = '⚡ Dash';
    dashBtn.disabled = dash === 0;
    dashBtn.style.cssText = `
      position: absolute;
      left: -140px;
      top: 50%;
      transform: translateY(-50%);
      padding: 10px 20px;
      background: ${dash > 0 ? '#66ddff' : '#555'};
      border: 2px solid ${dash > 0 ? '#88eeff' : '#666'};
      border-radius: 8px;
      color: ${dash > 0 ? '#000' : '#888'};
      cursor: ${dash > 0 ? 'pointer' : 'not-allowed'};
      font-weight: bold;
      font-size: 14px;
      opacity: ${dash > 0 ? '1' : '0.5'};
      z-index: 10;
      box-shadow: 0 4px 12px rgba(0,0,0,0.3);
    `;

    // Prevent tooltip from showing when hovering over button
    dashBtn.onmouseenter = (e) => {
      e.stopPropagation();
      hideTooltip();
      if (dash > 0) dashBtn.style.background = '#88eeff';
    };
    dashBtn.onmousemove = (e) => {
      e.stopPropagation();
    };
    dashBtn.onmouseleave = (e) => {
      e.stopPropagation();
      if (dash > 0) dashBtn.style.background = '#66ddff';
    };

    if (dash > 0) {
      dashBtn.onclick = () => showDashModal();
    }
    currentNode.appendChild(dashBtn);
  }

  // Add Reroll button (right side of current node) - always shown, grayed out if reroll === 0
  if (true) {
    const rerollBtn = document.createElement('button');
    rerollBtn.className = 'node-reroll-btn';
    rerollBtn.textContent = '🔄 Reroll';
    rerollBtn.disabled = reroll === 0;
    rerollBtn.style.cssText = `
      position: absolute;
      right: -140px;
      top: 50%;
      transform: translateY(-50%);
      padding: 10px 20px;
      background: ${reroll > 0 ? '#ffcc66' : '#555'};
      border: 2px solid ${reroll > 0 ? '#ffdd77' : '#666'};
      border-radius: 8px;
      color: ${reroll > 0 ? '#333' : '#888'};
      cursor: ${reroll > 0 ? 'pointer' : 'not-allowed'};
      font-weight: bold;
      font-size: 14px;
      opacity: ${reroll > 0 ? '1' : '0.5'};
      z-index: 10;
      box-shadow: 0 4px 12px rgba(0,0,0,0.3);
    `;

    // Prevent tooltip from showing when hovering over button
    rerollBtn.onmouseenter = (e) => {
      e.stopPropagation();
      hideTooltip();
      if (reroll > 0) rerollBtn.style.background = '#ffdd77';
    };
    rerollBtn.onmousemove = (e) => {
      e.stopPropagation();
    };
    rerollBtn.onmouseleave = (e) => {
      e.stopPropagation();
      if (reroll > 0) rerollBtn.style.background = '#ffcc66';
    };

    if (reroll > 0) {
      rerollBtn.onclick = () => {
        if (confirm('Reroll the current choices?')) {
          useReroll();
        }
      };
    }
    currentNode.appendChild(rerollBtn);
  }
}

// Remove Dash/Reroll buttons (called when choice is made)
function removeDashRerollButtons() {
  const dashBtn = document.querySelector('.node-dash-btn');
  const rerollBtn = document.querySelector('.node-reroll-btn');
  if (dashBtn) dashBtn.remove();
  if (rerollBtn) rerollBtn.remove();
}

// ===== GAME ADVANCEMENT =====

function advance(game, x, y, encounterType) {
  // Remove floating Dash/Reroll buttons from choice screen
  removeDashRerollButtons();

  // Clear current choices now that the player has picked one
  gameState.currentChoices = [];

  // Get current player icon position before clearing choices
  const oldPlayerIcon = document.getElementById('player-icon');
  let startY = gameState.currentY || 120;

  clearChoices();
  const current = document.querySelector('.node.current');
  if (current) {
    current.classList.remove('current');
    current.classList.add('past');
    // Remove old player icon
    const oldIcon = current.querySelector('#player-icon');
    if (oldIcon) oldIcon.remove();
    // Remove old ability buttons and finished button
    const oldSkipBtn = current.querySelector('.ability-skip-btn');
    const oldRerollBtn = current.querySelector('.ability-reroll-btn');
    const oldDashBtn = current.querySelector('.ability-dash-btn');
    const oldNodeDash = current.querySelector('.node-dash-btn');
    const oldNodeReroll = current.querySelector('.node-reroll-btn');
    const oldFinishBtn = current.querySelector('.finish');
    if (oldSkipBtn) oldSkipBtn.remove();
    if (oldRerollBtn) oldRerollBtn.remove();
    if (oldDashBtn) oldDashBtn.remove();
    if (oldNodeDash) oldNodeDash.remove();
    if (oldNodeReroll) oldNodeReroll.remove();
    if (oldFinishBtn) oldFinishBtn.remove();
  }

  const n = addNode(game, 'current', x, y);
  gameState.currentGame = game;
  gameState.visitedGames.push(game);
  gameState.currentY = y;

  const distance = bfsCached(game, gameState.amuletGame.name);
  const difficulty = gameState.totalGamesBeaten || 0;
  document.getElementById('distance-display').textContent = `Target: ${gameState.amuletGame.name} — ${distance} steps away | Difficulty: ${difficulty}`;

  // Update location display with current game info
  if (typeof updateLocationDisplay === 'function') {
    const gameData = games.find(g => g.name === game);
    const gameDescription = gameData?.description || 'No description available';
    updateLocationDisplay(game, gameDescription);
  }

  // Add player icon with animation
  if (gameState.character && PLAYER_CHARACTERS[gameState.character]) {
    const playerIcon = document.createElement('img');
    playerIcon.src = PLAYER_CHARACTERS[gameState.character].icon;
    playerIcon.id = 'player-icon';

    // Start from old position for animation
    playerIcon.style.cssText = `
      position: absolute;
      top: ${startY - y - 70}px;
      left: 50%;
      transform: translateX(-50%);
      max-width: 80px;
      max-height: 80px;
      min-width: 56px;
      min-height: 56px;
      object-fit: contain;
      image-rendering: pixelated;
      z-index: 100;
      pointer-events: none;
      transition: top 0.6s ease-in-out;
    `;
    n.appendChild(playerIcon);

    // Trigger animation after a brief delay
    setTimeout(() => {
      playerIcon.style.top = '-70px';
      playerIcon.style.animation = 'playerPulse 2s infinite';
    }, 50);
  }

  // Check if reached amulet game
  const isAmuletGame = game === gameState.amuletGame.name;

  if (!isAmuletGame) {
    // Regeneration trait: Every time you choose a game whose encounter isn't enemy combat, heal +1
    if (encounterType !== 'combat' && typeof hasTrait === 'function' && hasTrait('regeneration')) {
      health = Math.min(health + 1, maxHealth);
      gameState.health = health;
      if (typeof updateTopBar === 'function') {
        updateTopBar();
      }
    }

    // Trigger game status effects on visit (scales by difficulty)
    if (typeof triggerGameStatusEffects === 'function') {
      triggerGameStatusEffects(game);
    }

    // Trigger encounter based on type (these functions are in main.js)
    if (encounterType === 'combat') {
      const startCombat = () => {
        if (window.useDiceCombat && typeof showDiceCombatModal === 'function') {
          showDiceCombatModal();
        } else if (typeof showCombatModal === 'function') {
          showCombatModal();
        }
      };
      if (typeof showEventModal === 'function') {
        showEventModal(null, startCombat);
      } else {
        startCombat();
      }
    } else if (encounterType === 'event' && typeof showEventModal === 'function') {
      showEventModal();
    } else if (encounterType === 'shop' && typeof showShopModal === 'function') {
      showShopModal();
    }
  }

  // Always show Finished button (including for amulet game)
  showFinish(n, isAmuletGame);

  // Update verification curses display when entering gameplay phase
  if (typeof updateVerificationCursesDisplay === 'function') {
    updateVerificationCursesDisplay();
  }

  // Scroll to keep node vertically centered in viewport
  setTimeout(() => {
    const viewport = document.getElementById('path-viewport');
    if (viewport && n) {
      const viewportRect = viewport.getBoundingClientRect();
      const viewportCenter = viewportRect.height / 2;

      // Center the node vertically - keep current node in middle of screen
      const targetY = y - viewportCenter + 50; // 50px offset for node height

      viewport.scrollTo({
        top: targetY,
        behavior: 'smooth'
      });
    }
  }, 100);

  // Save game (function in main.js)
  if (typeof saveCurrentGame === 'function') {
    saveCurrentGame();
  }
}

// ===== FINISHED BUTTON =====

function showFinish(node, isAmuletGame = false) {
  const b = document.createElement('button');
  b.className = 'finish';
  b.textContent = 'Finished';

  if (isAmuletGame) {
    b.textContent = 'Take Amulet & Escape!';
    b.style.background = 'linear-gradient(145deg, gold, #cc9900)';
    b.style.color = '#000';
    b.style.fontWeight = 'bold';
  }

  b.onclick = () => {
    // Remove both buttons from DOM
    const skipBtn = node.querySelector('.ability-skip-btn');
    if (skipBtn) {
      skipBtn.remove();
    }
    b.remove();

    // Clear any pending Hades start boon selection timeout to prevent it from firing
    // after the player has already progressed (fixes game skipping issue)
    if (gameState.hadesStartBoonTimeout) {
      clearTimeout(gameState.hadesStartBoonTimeout);
      gameState.hadesStartBoonTimeout = null;
    }

    if (isAmuletGame) {
      // Mark game as finished first
      if (typeof markGameFinished === 'function' && gameState && gameState.currentGame) {
        markGameFinished(gameState.currentGame);
      }
      // Small delay to let difficulty counter update before escape phase
      setTimeout(() => {
        if (typeof startEscapePhase === 'function') {
          startEscapePhase();
        }
      }, 150);
    } else {
      // Show curse verification (includes Precision Landing trait), then mark finished, then item choice
      if (typeof showCurseVerificationModal === 'function') {
        showCurseVerificationModal(() => {
          // After curse/trait verification, mark game as finished
          if (typeof markGameFinished === 'function' && gameState && gameState.currentGame) {
            markGameFinished(gameState.currentGame);
          }

          // Small delay to let difficulty counter and other UI elements update visually
          // before showing the next modal
          setTimeout(() => {
            // Check if we're in the middle of the Colosseum event
            if (gameState.colosseumState && gameState.colosseumState.stage === 'first_fight') {
              // Show item choice first, then Colosseum choices
              if (typeof showItemChoiceModal === 'function') {
                // Check if Unstable Genome triggered
                const chestType = gameState.unstableGenomeTriggered ? 'large' : 'normal';
                if (gameState.unstableGenomeTriggered) {
                  gameState.unstableGenomeTriggered = false; // Clear flag
                }
                showItemChoiceModal(() => {
                  // After item selection, update stage and show Colosseum choices
                  gameState.colosseumState.stage = 'choice';
                  if (typeof showColosseumChoices === 'function') {
                    showColosseumChoices();
                  }
                }, chestType);
              }
            } else if (gameState.colosseumState && gameState.colosseumState.stage === 'champion') {
              // Show item choice first, then ask about attempts
              if (typeof showItemChoiceModal === 'function') {
                // Check if Unstable Genome triggered
                const chestType = gameState.unstableGenomeTriggered ? 'large' : 'normal';
                if (gameState.unstableGenomeTriggered) {
                  gameState.unstableGenomeTriggered = false; // Clear flag
                }
                showItemChoiceModal(() => {
                  // After item selection, ask if it took 3 or less attempts
                  if (typeof handleChampionResult === 'function') {
                    handleChampionResult();
                  }
                }, chestType);
              }
            } else {
              // Normal flow - show item choice
              if (typeof showItemChoiceModal === 'function') {
                // Check if Unstable Genome triggered - if so, show large chest (3 items)
                const chestType = gameState.unstableGenomeTriggered ? 'large' : 'normal';
                if (gameState.unstableGenomeTriggered) {
                  gameState.unstableGenomeTriggered = false; // Clear flag
                }
                showItemChoiceModal(null, chestType);
              }
            }
          }, 150); // Small delay for UI to update
        });
      } else {
        // Fallback if verification not available
        if (typeof markGameFinished === 'function' && gameState && gameState.currentGame) {
          markGameFinished(gameState.currentGame);
        }

        // Small delay to let difficulty counter and other UI elements update visually
        setTimeout(() => {
          // Check if we're in the middle of the Colosseum event
          if (gameState.colosseumState && gameState.colosseumState.stage === 'first_fight') {
            // Show item choice first, then Colosseum choices
            if (typeof showItemChoiceModal === 'function') {
              // Check if Unstable Genome triggered
              const chestType = gameState.unstableGenomeTriggered ? 'large' : 'normal';
              if (gameState.unstableGenomeTriggered) {
                gameState.unstableGenomeTriggered = false; // Clear flag
              }
              showItemChoiceModal(() => {
                // After item selection, update stage and show Colosseum choices
                gameState.colosseumState.stage = 'choice';
                if (typeof showColosseumChoices === 'function') {
                  showColosseumChoices();
                }
              }, chestType);
            }
          } else if (gameState.colosseumState && gameState.colosseumState.stage === 'champion') {
            // Show item choice first, then ask about attempts
            if (typeof showItemChoiceModal === 'function') {
              // Check if Unstable Genome triggered
              const chestType = gameState.unstableGenomeTriggered ? 'large' : 'normal';
              if (gameState.unstableGenomeTriggered) {
                gameState.unstableGenomeTriggered = false; // Clear flag
              }
              showItemChoiceModal(() => {
                // After item selection, ask if it took 3 or less attempts
                if (typeof handleChampionResult === 'function') {
                  handleChampionResult();
                }
              }, chestType);
            }
          } else {
            // Normal flow - show item choice
            if (typeof showItemChoiceModal === 'function') {
              // Check if Unstable Genome triggered - if so, show large chest (3 items)
              const chestType = gameState.unstableGenomeTriggered ? 'large' : 'normal';
              if (gameState.unstableGenomeTriggered) {
                gameState.unstableGenomeTriggered = false; // Clear flag
              }
              showItemChoiceModal(null, chestType);
            }
          }
        }, 150); // Small delay for UI to update
      }
    }
  };

  // Prevent button from triggering tooltip events
  b.onmouseenter = (e) => {
    hideTooltip();
    e.stopPropagation();
  };
  b.onmousemove = (e) => {
    e.stopPropagation();
  };
  b.onmouseleave = (e) => {
    e.stopPropagation();
  };

  node.appendChild(b);

  // Add Skip button to the left of Finished button (only if skip > 0)
  if (skip > 0) {
    const skipBtn = document.createElement('button');
    skipBtn.className = 'ability-skip-btn';
    skipBtn.textContent = '⏭ Skip';
    skipBtn.disabled = false;
    skipBtn.style.cssText = `
      position: absolute;
      left: -70px;
      bottom: -50px;
      padding: 8px 16px;
      background: #ff9966;
      border: 2px solid #ffaa77;
      border-radius: 8px;
      color: #fff;
      cursor: pointer;
      font-weight: bold;
      font-size: 13px;
      opacity: 1;
      z-index: 100;
    `;
    skipBtn.onclick = () => {
      if (confirm('Skip this game and move to the next choice?')) {
        // Remove both buttons from DOM
        const finishedBtn = node.querySelector('.finish');
        if (finishedBtn) {
          finishedBtn.remove();
        }
        skipBtn.remove();

        useSkip();
      }
    };
    skipBtn.onmouseenter = () => {
      skipBtn.style.background = '#ffaa77';
      hideTooltip();
    };
    skipBtn.onmouseleave = () => {
      skipBtn.style.background = '#ff9966';
    };
    node.appendChild(skipBtn);
  }
}

// Export exploration functions globally
window.clearChoices = clearChoices;
window.clearAllArrows = clearAllArrows;
window.spawnChoices = spawnChoices;
window.addDashRerollButtons = addDashRerollButtons;
window.removeDashRerollButtons = removeDashRerollButtons;
window.advance = advance;
window.showFinish = showFinish;
