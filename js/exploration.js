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
  // Insane overheat: force a hard combat before showing movement choices
  if (gameState.pendingInsaneHardCombat) {
    gameState.pendingInsaneHardCombat = false;
    if (typeof showCombatModal === 'function') {
      showCombatModal();
      return; // showCombatModal will call spawnChoices() on win via normal combat flow
    }
  }

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

  // Apply pending one-shot statuses (e.g. from non-Hades effects) to game choices
  if (gameState.pendingLocationStatuses && gameState.pendingLocationStatuses.length > 0) {
    gameState.pendingLocationStatuses.forEach(statusName => {
      if (opts.length > 0) {
        const randomIndex = Math.floor(Math.random() * opts.length);
        const targetGame = opts[randomIndex];
        if (typeof addGameStatus === 'function') {
          addGameStatus(targetGame, statusName.toLowerCase());
        }
      }
    });
    gameState.pendingLocationStatuses = [];
  }

  // Hades location effect: while at a Hades location, at least one choice always gets
  // the boon's associated status (the "cost" listed in each boon description).
  if (gameState.location && typeof hasGodBoonChoice === 'function' && hasGodBoonChoice(gameState.location) && opts.length > 0) {
    const activeBoons = (gameState.inventory || []).filter(item => item.type === 'Boon');
    const boonStatuses = [];
    activeBoons.forEach(boon => {
      const statusMatch = (boon.description || '').match(/will be (\w+)/i);
      if (statusMatch) boonStatuses.push(statusMatch[1].toLowerCase());
    });
    if (boonStatuses.length > 0 && typeof addGameStatus === 'function') {
      const statusName = boonStatuses[Math.floor(Math.random() * boonStatuses.length)];
      const idx = Math.floor(Math.random() * opts.length);
      addGameStatus(opts[idx], statusName);
    }
  }

  // Store current choices so the map can highlight them
  gameState.currentChoices = [...opts];

  // Pre-generate enemy encounters and post-combat options for each choice node
  if (!gameState.choiceDetails) gameState.choiceDetails = {};
  opts.forEach(g => {
    if (!gameState.choiceDetails[g]) {
      gameState.choiceDetails[g] = {
        enemies: preGenerateEnemiesForGame(g),
        postCombatOptions: pickTwoPostCombatOptions()
      };
    }
  });

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
    let encounterType;

    // Find the game object
    const game = games.find(game => game.name === g);

    // Get encounter type from current run's assignments
    encounterType = gameState.encounterTypes?.[g];

    if (!encounterType) {
      // Fallback if encounterType not found (shouldn't happen)
      console.warn(`No encounterType found for game: ${g}, using fallback`);
      encounterType = 'combat';
    }

    const n = addNode(g, 'choice', nx, ny);

    // Revisit indicator: banner above the node when the player has already beaten this game
    if (gameState.finishedGames && gameState.finishedGames.includes(g)) {
      const revisitBanner = document.createElement('div');
      revisitBanner.title = 'Already beaten — revisiting grants +1 Dash';
      revisitBanner.textContent = '💨 +1 Dash on Revisit';
      revisitBanner.style.cssText = [
        'position:absolute',
        'bottom:calc(100% + 6px)',
        'left:50%',
        'transform:translateX(-50%)',
        'white-space:nowrap',
        'background:#1a3a4a',
        'color:#88ddff',
        'border:1px solid #44aacc',
        'border-radius:4px',
        'padding:2px 8px',
        'font-size:11px',
        'font-weight:bold',
        'letter-spacing:0.3px',
        'box-shadow:0 2px 6px rgba(0,0,0,0.5)',
        'pointer-events:none',
        'z-index:5',
      ].join(';');
      n.appendChild(revisitBanner);
    }

    // Check if this is the amulet game
    const isAmuletGame = (g === gameState.amuletGame.name);

    if (isAmuletGame) {
      encounterType = 'amulet';
    }

    // Game-type badge — colored pill showing mechanical type (Action/Deckbuilding/etc.)
    const typeColors = { action: '#c0392b', deckbuilding: '#7d3c98', strategy: '#1a6fa0', traditional: '#1e8449' };
    const badgeLabel = isAmuletGame ? '🏺 Amulet' : (game?.type || 'Unknown');
    const badgeColor = isAmuletGame ? '#b7950b' : (typeColors[(game?.type || '').toLowerCase()] || '#555');
    const typeBadge = document.createElement('span');
    typeBadge.textContent = badgeLabel;
    typeBadge.style.cssText = [
      'position:absolute',
      'bottom:-12px',
      'left:50%',
      'transform:translateX(-50%)',
      'background:' + badgeColor,
      'color:#fff',
      'border-radius:4px',
      'padding:2px 7px',
      'font-size:9px',
      'font-weight:bold',
      'white-space:nowrap',
      'border:1px solid rgba(0,0,0,0.35)',
      'box-shadow:0 1px 4px rgba(0,0,0,0.4)',
      'pointer-events:none',
      'z-index:5',
      'letter-spacing:0.3px',
    ].join(';');
    n.appendChild(typeBadge);

    // Store encounter type on the node
    n.dataset.encounterType = encounterType;

    n.onclick = () => showNodeDetailModal(g, nx, ny, encounterType, {
      onFight: () => advance(g, nx, ny, encounterType)
    });
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

  // Scroll viewport to ensure choice nodes are visible
  requestAnimationFrame(() => {
    const viewport = document.getElementById('path-viewport');
    if (!viewport) return;
    const baseY = gameState.currentY + 200;
    const choiceBottom = baseY + 180; // node height ~60px + type badge ~12px + row spacing buffer
    const viewBottom = viewport.scrollTop + viewport.clientHeight;
    if (choiceBottom > viewBottom - 20) {
      viewport.scrollTo({ top: choiceBottom - viewport.clientHeight + 80, behavior: 'smooth' });
    }
  });
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
      // Small delay before escape phase
      setTimeout(() => {
        if (typeof startEscapePhase === 'function') {
          startEscapePhase();
        }
      }, 150);
    } else {
      // Show curse verification (Precision Landing trait), then item choice
      if (typeof showCurseVerificationModal === 'function') {
        showCurseVerificationModal(() => {
          // Small delay to let UI elements update visually before showing the next modal
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
        // Small delay to let UI elements update visually
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

// ===== NODE DETAIL MODAL =====

const _POST_COMBAT_META = {
  rest:     { icon: '🛌', label: 'Rest',     desc: 'Heal 33% of max HP' },
  smith:    { icon: '⚒️',  label: 'Smith',    desc: 'Upgrade 2 cards free' },
  shop:     { icon: '🛒', label: 'Shop',     desc: 'Buy items' },
  movement: { icon: '🗺️', label: 'Movement', desc: 'Navigate terrain' },
};

/**
 * Pre-generate an enemy list for a given game node using the same weight-based
 * logic as buildWeightedEncounter(), but parameterised by game name.
 */
function preGenerateEnemiesForGame(gameName) {
  const gamesBeaten = gameState.totalGamesBeaten || 0;
  const thresholds = (typeof DIFFICULTY_THRESHOLDS !== 'undefined')
    ? DIFFICULTY_THRESHOLDS : { MEDIUM: 4, HARD: 8, INSANE: 12 };
  let currentTier;
  if (gamesBeaten >= thresholds.HARD) currentTier = 'High';
  else if (gamesBeaten >= thresholds.MEDIUM) currentTier = 'Medium';
  else currentTier = 'Low';

  const TYPE_MAP = { Action: 'Strength', Deckbuilding: 'Charisma', Strategy: 'Intelligence', Traditional: 'Dexterity' };
  const gameObj = typeof games !== 'undefined' ? games.find(g => g.name === gameName) : null;
  const requiredType = gameObj ? (TYPE_MAP[gameObj.type] || null) : null;

  const tierOrder = ['Low', 'Medium', 'High'];
  const maxTierIdx = tierOrder.indexOf(currentTier);
  const allEnemies = typeof ENEMIES_DATA !== 'undefined' ? ENEMIES_DATA : [];

  let pool = allEnemies.filter(e =>
    e.weight !== null && e.weight !== undefined && e.difficulty !== null &&
    tierOrder.indexOf(e.difficulty) <= maxTierIdx &&
    (!requiredType || e.type === requiredType)
  );
  if (pool.length === 0) {
    pool = allEnemies.filter(e =>
      e.weight !== null && e.weight !== undefined && e.difficulty !== null &&
      tierOrder.indexOf(e.difficulty) <= maxTierIdx
    );
  }
  if (pool.length === 0) return [];

  const combatsCompleted = gameState.totalCombatsCompleted || 0;
  let budget;
  if (combatsCompleted === 0) budget = 2;
  else if (currentTier === 'Low') budget = 4;
  else if (currentTier === 'Medium') budget = 6;
  else budget = 9;

  const selected = [];
  let remaining = budget;
  while (remaining > 0 && selected.length < 4) {
    const fitting = pool.filter(e => e.weight <= remaining);
    if (fitting.length === 0) break;
    const maxW = Math.max(...fitting.map(e => e.weight));
    const targetW = Math.floor(Math.random() * maxW) + 1;
    let cands = fitting.filter(e => Math.ceil(e.weight) === targetW);
    if (cands.length === 0) cands = fitting;
    const chosen = cands[Math.floor(Math.random() * cands.length)];
    selected.push(chosen);
    remaining -= chosen.weight;
  }
  return selected;
}

/** Pick 2 distinct post-combat option keys from the available pool. */
function pickTwoPostCombatOptions() {
  const keys = Object.keys(_POST_COMBAT_META);
  // Shuffle and take first 2
  for (let i = keys.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [keys[i], keys[j]] = [keys[j], keys[i]];
  }
  return keys.slice(0, 2);
}

/**
 * Show the node detail modal for a game node.
 * @param {string} gameName
 * @param {number|null} x - Node x position (null for start/map nodes)
 * @param {number|null} y - Node y position (null for start/map nodes)
 * @param {string} encounterType - 'combat', 'event', 'shop', 'amulet'
 * @param {Object} opts
 *   opts.fromMap    {boolean} - Blur enemies, hide Fight! button (read-only map view)
 *   opts.onFight    {function} - Callback when Fight! is clicked (if omitted, advance() is used)
 */
function showNodeDetailModal(gameName, x, y, encounterType, opts = {}) {
  const fromMap = opts.fromMap || false;
  const onFight = opts.onFight || null;

  const game = typeof games !== 'undefined' ? games.find(g => g.name === gameName) : null;
  const details = (gameState.choiceDetails && gameState.choiceDetails[gameName]) || {};
  const enemies = details.enemies || preGenerateEnemiesForGame(gameName);
  const postCombatOptions = details.postCombatOptions || pickTwoPostCombatOptions();

  const coverImage = game?.coverImage || 'images/covers/no-cover.svg';
  const gameType = game?.type || 'Unknown';
  const typeColors = { Action: '#c0392b', Deckbuilding: '#7d3c98', Strategy: '#1a6fa0', Traditional: '#1e8449' };
  const typeColor = typeColors[gameType] || '#555';

  // ---- Enemy cards ----
  const DIFF_COLORS = { Low: '#2ecc71', Medium: '#f39c12', High: '#e74c3c' };
  const enemyCardsHTML = enemies.map(e => {
    const imgPath = typeof getEnemyImagePath === 'function' ? getEnemyImagePath(e.name) : '';
    const dc = DIFF_COLORS[e.difficulty] || '#888';
    return `
      <div style="background:#0d1b2a;border:1px solid #2a4a6a;border-radius:8px;padding:8px;display:flex;flex-direction:column;align-items:center;gap:6px;text-align:center;">
        <img src="${imgPath}" alt="${e.name}"
          style="width:52px;height:52px;object-fit:contain;border-radius:4px;background:#0a0f1a;flex-shrink:0;"
          onerror="this.style.visibility='hidden'">
        <div style="min-width:0;width:100%;">
          <div style="font-weight:bold;color:#e6d5b8;font-size:12px;margin-bottom:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${e.name}</div>
          <div style="color:#aaa;font-size:10px;margin-bottom:3px;">❤️ ${e.hpMin}–${e.hpMax} &nbsp;·&nbsp; ⚔️ ${e.type}</div>
          <div style="font-size:10px;">
            <span style="background:${dc}22;color:${dc};border:1px solid ${dc}44;border-radius:3px;padding:1px 5px;font-size:9px;">${e.difficulty}</span>
          </div>
        </div>
      </div>`;
  }).join('');

  const blurWrap = fromMap
    ? `style="filter:blur(5px);pointer-events:none;user-select:none;"`
    : '';
  const blurOverlay = fromMap ? `
    <div style="position:absolute;inset:0;background:rgba(0,0,0,0.35);border-radius:8px;display:flex;align-items:center;justify-content:center;z-index:2;">
      <div style="color:#aaa;font-size:12px;text-align:center;padding:10px;">
        <div style="font-size:20px;margin-bottom:6px;">🔍</div>
        Scout from the exploration view to reveal enemies
      </div>
    </div>` : '';

  // ---- Post-combat preview ----
  const optCardsHTML = postCombatOptions.map(key => {
    const m = _POST_COMBAT_META[key] || { icon: '❓', label: key, desc: '' };
    return `
      <div style="flex:1;background:#111e11;border:1px solid #2a4a2a;border-radius:8px;padding:12px;text-align:center;">
        <div style="font-size:26px;margin-bottom:5px;">${m.icon}</div>
        <div style="font-weight:bold;color:#e6d5b8;font-size:12px;margin-bottom:3px;">${m.label}</div>
        <div style="color:#777;font-size:10px;">${m.desc}</div>
      </div>`;
  }).join('');

  // ---- Stash args for inline onclick reuse ----
  window._ndmArgs = { gameName, x, y, encounterType, fromMap };

  const mapBtnCode = `showGameMapPreview(window._ndmArgs.gameName, () => showNodeDetailModal(window._ndmArgs.gameName, window._ndmArgs.x, window._ndmArgs.y, window._ndmArgs.encounterType, {fromMap: window._ndmArgs.fromMap, onFight: window._ndmFight}))`;

  // Fight button (only when not fromMap)
  let fightBtnHTML = '';
  if (!fromMap) {
    window._ndmFight = onFight || (() => advance(gameName, x, y, encounterType));
    fightBtnHTML = `
      <button onclick="closeGameModal(); window._ndmFight && window._ndmFight();"
        style="background:#c0392b;color:white;border:none;border-radius:6px;padding:10px 28px;font-size:14px;font-weight:bold;cursor:pointer;letter-spacing:0.4px;">
        ⚔️ Fight!
      </button>`;
  }

  const isAmulet = encounterType === 'amulet';

  createGameModal(`
    <div style="width:460px;max-width:92vw;overflow:hidden;border-radius:10px;background:#0f0f1a;">
      <div style="position:relative;height:300px;overflow:hidden;background:#0a0f1a;">
        <img src="${coverImage}" alt="${gameName}"
          style="width:100%;height:100%;object-fit:cover;object-position:center center;display:block;"
          onerror="this.style.display='none'">
        <div style="position:absolute;inset:0;background:linear-gradient(to bottom,rgba(0,0,0,0.05) 40%,rgba(0,0,0,0.85) 100%);"></div>
        <button onclick="${mapBtnCode}"
          style="position:absolute;top:10px;right:10px;background:rgba(0,0,0,0.55);border:1px solid #44aacc;border-radius:5px;color:#88ccff;padding:4px 10px;font-size:11px;cursor:pointer;font-weight:bold;">
          🗺 Map
        </button>
        <div style="position:absolute;bottom:12px;left:14px;right:60px;">
          <div style="font-weight:bold;color:white;font-size:15px;text-shadow:0 2px 4px rgba(0,0,0,0.9);margin-bottom:5px;">${gameName}</div>
          <span style="background:${typeColor};color:white;padding:2px 9px;border-radius:4px;font-size:10px;font-weight:bold;letter-spacing:0.3px;">${gameType}</span>
          ${isAmulet ? '<span style="background:#b7950b;color:white;padding:2px 9px;border-radius:4px;font-size:10px;font-weight:bold;margin-left:6px;">🏺 Amulet</span>' : ''}
        </div>
      </div>

      <div style="padding:16px;">
        <div style="margin-bottom:14px;">
          <div style="color:#e6d5b8;font-size:11px;font-weight:bold;letter-spacing:0.6px;margin-bottom:8px;text-transform:uppercase;opacity:0.65;">Enemies</div>
          <div style="position:relative;">
            <div ${blurWrap}>
              <div style="display:grid;grid-template-columns:1fr 1fr;gap:7px;">
                ${enemies.length > 0 ? enemyCardsHTML : '<div style="color:#555;font-size:12px;text-align:center;padding:12px;grid-column:1/-1;">No enemy data available</div>'}
              </div>
            </div>
            ${blurOverlay}
          </div>
        </div>

        ${isAmulet ? '' : `
        <div style="margin-bottom:14px;">
          <div style="color:#e6d5b8;font-size:11px;font-weight:bold;letter-spacing:0.6px;margin-bottom:8px;text-transform:uppercase;opacity:0.65;">After Victory</div>
          <div style="display:flex;gap:10px;">${optCardsHTML}</div>
        </div>`}

        <div style="display:flex;justify-content:space-between;align-items:center;padding-top:4px;">
          <button onclick="closeGameModal()"
            style="background:#2a2a3a;color:#aaa;border:1px solid #444;border-radius:6px;padding:8px 20px;font-size:13px;cursor:pointer;">
            ← Back
          </button>
          ${fightBtnHTML}
        </div>
      </div>
    </div>
  `);

  // Centre the modal both horizontally and vertically
  const overlay = document.getElementById('game-modal');
  if (overlay) {
    overlay.style.alignItems = 'center';
    overlay.style.paddingTop = '0';
    overlay.style.padding = '16px';
  }
  const mc = document.querySelector('#game-modal .modal-content');
  if (mc) {
    mc.style.width = 'auto';
    mc.style.maxWidth = '95vw';
    mc.style.maxHeight = '90vh';
    mc.style.overflowY = 'auto';
    mc.style.padding = '0';
    mc.style.background = 'transparent';
    mc.style.border = 'none';
    mc.style.boxShadow = 'none';
  }
}

/** Called from map-view onclick for choice nodes — opens modal in read-only mode. */
function openNodeModalFromMap(gameName) {
  const encounterType = gameState.encounterTypes?.[gameName] || 'combat';
  showNodeDetailModal(gameName, null, null, encounterType, { fromMap: true });
}

// Export exploration functions globally
window.clearChoices = clearChoices;
window.clearAllArrows = clearAllArrows;
window.spawnChoices = spawnChoices;
window.addDashRerollButtons = addDashRerollButtons;
window.removeDashRerollButtons = removeDashRerollButtons;
window.advance = advance;
window.showFinish = showFinish;
window.showNodeDetailModal = showNodeDetailModal;
window.openNodeModalFromMap = openNodeModalFromMap;
window.preGenerateEnemiesForGame = preGenerateEnemiesForGame;
window.pickTwoPostCombatOptions = pickTwoPostCombatOptions;
