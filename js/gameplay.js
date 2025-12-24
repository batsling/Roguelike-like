// ===== GAMEPLAY.JS - Core Game Flow, Pathfinding, Node Management =====
//
// This module handles:
// - Breadth-first search (BFS) for pathfinding
// - Node creation and rendering
// - Game advancement and progression
// - Path visualization
// - Game state rendering

// ===== DOM REFERENCES =====
// These will be set in main.js
let pathContainer, linesSvg, tooltip, viewport;

function initGameplayDOM() {
  pathContainer = document.getElementById('path-container');
  linesSvg = document.getElementById('connection-lines');
  tooltip = document.getElementById('game-tooltip');
  viewport = document.getElementById('path-viewport');
}

// ===== PATHFINDING =====

function bfs(start, goal) {
  const queue = [[start, 0]];
  const visited = new Set([start]);

  while (queue.length > 0) {
    const [node, dist] = queue.shift();
    if (node === goal) return dist;

    getGameConnections(node).forEach(neighbor => {
      if (!visited.has(neighbor)) {
        visited.add(neighbor);
        queue.push([neighbor, dist + 1]);
      }
    });
  }
  return '∞';
}

function getGameConnections(gameName) {
  const connected = [];

  // Find the game object
  const game = games.find(g => g.name === gameName);

  if (game && game.gamesInfluenced) {
    // Add all games this game influences
    connected.push(...game.gamesInfluenced);
  }

  // Find all games that influence this game
  games.forEach(g => {
    if (g.gamesInfluenced && g.gamesInfluenced.includes(gameName)) {
      connected.push(g.name);
    }
  });

  return [...new Set(connected)]; // Remove duplicates
}

// ===== NODE CREATION =====

function addNode(name, cls, x, y) {
  const d = document.createElement('div');
  d.className = `node ${cls}`;
  d.style.left = x + 'px';
  d.style.top = y + 'px';
  d.textContent = name;

  d.onmouseenter = e => showTooltip(e, name);
  d.onmousemove = e => moveTooltip(e);
  d.onmouseleave = hideTooltip;

  pathContainer.appendChild(d);
  return d;
}

// ===== TOOLTIPS =====

function showTooltip(e, name) {
  const game = games.find(g => g.name === name);
  if (!game) return;

  // Separate influences and influenced by
  const influences = game.gamesInfluenced || []; // Games this game influenced
  const influencedBy = []; // Games that influenced this game

  // Find all games that influence this game
  games.forEach(g => {
    if (g.gamesInfluenced && g.gamesInfluenced.includes(name)) {
      influencedBy.push(g.name);
    }
  });

  let connectionsHTML = '';
  if (influencedBy.length > 0) {
    connectionsHTML += `<div style="margin-top: 8px;"><strong style="color: #4CAF50;">Influenced By:</strong>${influencedBy.map(g => `<div>${g} → ${name}</div>`).join('')}</div>`;
  }
  if (influences.length > 0) {
    connectionsHTML += `<div style="margin-top: 8px;"><strong style="color: #9b59b6;">Influences:</strong>${influences.map(g => `<div>${name} → ${g}</div>`).join('')}</div>`;
  }
  if (influencedBy.length === 0 && influences.length === 0) {
    connectionsHTML = '<div style="margin-top: 8px; color: #888;">No connections</div>';
  }

  // Build tags HTML
  let tagsHTML = '';
  if (game.tags && game.tags.length > 0) {
    tagsHTML = `
      <div style="margin-top: 10px; padding-top: 8px; border-top: 1px solid rgba(255,255,255,0.2);">
        <div style="font-size: 11px; color: #888; margin-bottom: 4px;">Tags:</div>
        <div style="display: flex; flex-wrap: wrap; gap: 4px;">
          ${game.tags.map(tag => `
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

  tooltip.innerHTML = `<h4>${name}</h4>
    <div>Release Year: ${game.year || '—'}</div>
    <div>Type: ${game.type || '—'}</div>
    <div class="mini-map">${connectionsHTML}</div>
    ${tagsHTML}`;
  tooltip.style.opacity = 1;
  tooltip.style.display = 'block';
  moveTooltip(e);
}

function moveTooltip(e) {
  tooltip.style.left = e.clientX + 14 + 'px';
  tooltip.style.top = e.clientY + 14 + 'px';
}

function hideTooltip() {
  tooltip.style.opacity = 0;
  setTimeout(() => {
    tooltip.style.display = 'none';
  }, 150);
}

// ===== LINE DRAWING =====

function drawArrowLine(fromNode, toNode) {
  const r1 = fromNode.getBoundingClientRect();
  const r2 = toNode.getBoundingClientRect();
  const pr = pathContainer.getBoundingClientRect();

  // Calculate start and end points
  const x1 = r1.left + r1.width / 2 - pr.left;
  const y1 = r1.bottom - pr.top;
  const x2 = r2.left + r2.width / 2 - pr.left;
  const y2 = r2.top - pr.top;

  // Create the line
  const l = document.createElementNS('http://www.w3.org/2000/svg', 'line');
  l.setAttribute('x1', x1);
  l.setAttribute('y1', y1);
  l.setAttribute('x2', x2);
  l.setAttribute('y2', y2);
  l.setAttribute('stroke', '#ffdd00');
  l.setAttribute('stroke-width', '6');
  l.setAttribute('opacity', '1');
  l.setAttribute('stroke-dasharray', '8,4');
  l.setAttribute('marker-end', 'url(#arrowhead)');
  l.classList.add('choice-arrow');
  linesSvg.appendChild(l);

  // Create arrowhead marker if it doesn't exist
  if (!document.getElementById('arrowhead')) {
    createArrowheadMarker();
  }
}

function drawPastLine(fromNode, toNode) {
  const r1 = fromNode.getBoundingClientRect();
  const r2 = toNode.getBoundingClientRect();
  const pr = pathContainer.getBoundingClientRect();

  const l = document.createElementNS('http://www.w3.org/2000/svg', 'line');
  l.setAttribute('x1', r1.left + r1.width / 2 - pr.left);
  l.setAttribute('y1', r1.bottom - pr.top);
  l.setAttribute('x2', r2.left + r2.width / 2 - pr.left);
  l.setAttribute('y2', r2.top - pr.top);
  l.setAttribute('stroke', '#aaa');
  l.setAttribute('stroke-width', '3');
  l.setAttribute('opacity', '0.6');
  linesSvg.appendChild(l);
}

function createArrowheadMarker() {
  const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');
  const marker = document.createElementNS('http://www.w3.org/2000/svg', 'marker');
  marker.setAttribute('id', 'arrowhead');
  marker.setAttribute('markerWidth', '10');
  marker.setAttribute('markerHeight', '10');
  marker.setAttribute('refX', '9');
  marker.setAttribute('refY', '3');
  marker.setAttribute('orient', 'auto');
  marker.setAttribute('markerUnits', 'strokeWidth');

  const polygon = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
  polygon.setAttribute('points', '0 0, 10 3, 0 6');
  polygon.setAttribute('fill', '#ffdd00');

  marker.appendChild(polygon);
  defs.appendChild(marker);
  linesSvg.appendChild(defs);
}

// ===== CHOICE MANAGEMENT =====

function clearChoices() {
  // Remove choice nodes
  document.querySelectorAll('.node.choice').forEach(n => n.remove());

  // Clear all lines
  while (linesSvg.lastChild) linesSvg.removeChild(linesSvg.lastChild);

  // Recreate arrowhead marker
  createArrowheadMarker();

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

  // Allow all connections (games can be repeated)
  const gamesToChooseFrom = allConnections;

  // Randomly shuffle and take fov number of choices
  const shuffled = [...gamesToChooseFrom].sort(() => Math.random() - 0.5);
  const numChoices = Math.max(1, fov || 3); // Use fov stat, default to 3
  const opts = shuffled.slice(0, Math.min(numChoices, shuffled.length));

  // Dynamic spacing based on number of choices
  // Ensure minimum spacing of 240px (220px max node width + 20px gap)
  const spacing = Math.max(240, Math.min(320, 800 / opts.length));
  const sx = 450 - ((opts.length - 1) * spacing) / 2;
  const currentNode = document.querySelector('.node.current');

  opts.forEach((g, i) => {
    const nx = sx + i * spacing;
    const ny = gameState.currentY + 200;

    // Determine encounter type
    const encounterRoll = Math.random() * 100;
    let encounterType, encounterIcon, encounterColor;

    if (encounterRoll < 75) {
      encounterType = 'combat';
      encounterIcon = '!';
      // Get game type for color
      const game = games.find(game => game.name === g);
      if (game) {
        switch(game.type.toLowerCase()) {
          case 'action': encounterColor = 'red'; break;
          case 'deckbuilding': encounterColor = 'purple'; break;
          case 'strategy': encounterColor = 'blue'; break;
          default: encounterColor = 'green'; break;
        }
      } else {
        encounterColor = 'green';
      }
    } else if (encounterRoll < 90) {
      encounterType = 'event';
      encounterIcon = '?';
      encounterColor = 'purple';
    } else {
      encounterType = 'shop';
      encounterIcon = '$';
      encounterColor = 'gold';
    }

    const n = addNode(g, 'choice', nx, ny);

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
    const currentNode = document.querySelector('.node.current');
    const choiceNodes = document.querySelectorAll('.node.choice');

    if (currentNode) {
      choiceNodes.forEach(choiceNode => {
        drawArrowLine(currentNode, choiceNode);
      });
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

  // Add Dash button (left side of current node)
  if (dash > 0 || true) {  // Always show, but gray out if dash === 0
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

  // Add Reroll button (right side of current node)
  if (reroll > 0 || true) {  // Always show, but gray out if reroll === 0
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

// ===== OLD ABILITY BUTTONS (DEPRECATED) =====

function addAbilityButtons(node) {
  // Add Dash button (left side)
  if (dash > 0 || true) {  // Always show, but gray out if dash === 0
    const dashBtn = document.createElement('button');
    dashBtn.className = 'ability-dash-btn';
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
    `;
    if (dash > 0) {
      dashBtn.onclick = () => showDashModal();
      dashBtn.onmouseenter = () => {
        if (dash > 0) dashBtn.style.background = '#88eeff';
      };
      dashBtn.onmouseleave = () => {
        if (dash > 0) dashBtn.style.background = '#66ddff';
      };
    }
    node.appendChild(dashBtn);
  }

  // Add Skip button (bottom left of node, left of Finished button)
  if (skip > 0 || true) {  // Always show, but gray out if skip === 0
    const skipBtn = document.createElement('button');
    skipBtn.className = 'ability-skip-btn';
    skipBtn.textContent = '⏭ Skip';
    skipBtn.disabled = skip === 0;
    skipBtn.style.cssText = `
      position: absolute;
      left: -70px;
      bottom: -50px;
      padding: 8px 16px;
      background: ${skip > 0 ? '#ff9966' : '#555'};
      border: 2px solid ${skip > 0 ? '#ffaa77' : '#666'};
      border-radius: 8px;
      color: ${skip > 0 ? '#fff' : '#888'};
      cursor: ${skip > 0 ? 'pointer' : 'not-allowed'};
      font-weight: bold;
      font-size: 13px;
      opacity: ${skip > 0 ? '1' : '0.5'};
      z-index: 10;
    `;
    if (skip > 0) {
      skipBtn.onclick = () => {
        if (confirm('Skip this game and move to the next choice?')) {
          useSkip();
        }
      };
      skipBtn.onmouseenter = () => {
        if (skip > 0) skipBtn.style.background = '#ffaa77';
      };
      skipBtn.onmouseleave = () => {
        if (skip > 0) skipBtn.style.background = '#ff9966';
      };
    }
    node.appendChild(skipBtn);
  }

  // Add Reroll button (right side)
  if (reroll > 0 || true) {  // Always show, but gray out if reroll === 0
    const rerollBtn = document.createElement('button');
    rerollBtn.className = 'ability-reroll-btn';
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
    `;
    if (reroll > 0) {
      rerollBtn.onclick = () => {
        if (confirm('Reroll the current choices?')) {
          useReroll();
        }
      };
      rerollBtn.onmouseenter = () => {
        if (reroll > 0) rerollBtn.style.background = '#ffdd77';
      };
      rerollBtn.onmouseleave = () => {
        if (reroll > 0) rerollBtn.style.background = '#ffcc66';
      };
    }
    node.appendChild(rerollBtn);
  }
}

// ===== GAME ADVANCEMENT =====

function advance(game, x, y, encounterType) {
  // Remove floating Dash/Reroll buttons from choice screen
  removeDashRerollButtons();

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
    // Remove old ability buttons
    const oldSkipBtn = current.querySelector('.ability-skip-btn');
    const oldRerollBtn = current.querySelector('.ability-reroll-btn');
    const oldDashBtn = current.querySelector('.ability-dash-btn');
    const oldNodeDash = current.querySelector('.node-dash-btn');
    const oldNodeReroll = current.querySelector('.node-reroll-btn');
    if (oldSkipBtn) oldSkipBtn.remove();
    if (oldRerollBtn) oldRerollBtn.remove();
    if (oldDashBtn) oldDashBtn.remove();
    if (oldNodeDash) oldNodeDash.remove();
    if (oldNodeReroll) oldNodeReroll.remove();
  }

  const n = addNode(game, 'current', x, y);
  gameState.currentGame = game;
  gameState.visitedGames.push(game);
  gameState.currentY = y;

  document.getElementById('distance-display').textContent = `Target: ${gameState.amuletGame.name} — ${bfs(game, gameState.amuletGame.name)} steps away`;

  // Add player icon with animation
  if (gameState.character && PLAYER_CHARACTERS[gameState.character]) {
    const playerIcon = document.createElement('img');
    playerIcon.src = PLAYER_CHARACTERS[gameState.character].icon;
    playerIcon.id = 'player-icon';

    // Start from old position for animation
    playerIcon.style.cssText = `
      position: absolute;
      top: ${startY - y - 55}px;
      left: 50%;
      transform: translateX(-50%);
      width: 48px;
      height: 48px;
      image-rendering: pixelated;
      z-index: 100;
      pointer-events: none;
      transition: top 0.6s ease-in-out;
    `;
    n.appendChild(playerIcon);

    // Trigger animation after a brief delay
    setTimeout(() => {
      playerIcon.style.top = '-55px';
      playerIcon.style.animation = 'playerPulse 2s infinite';
    }, 50);
  }

  // Check if reached amulet game
  const isAmuletGame = game === gameState.amuletGame.name;

  if (!isAmuletGame) {
    // Store the encounter type for later
    gameState.nextEncounterType = encounterType;

    // Trigger encounter based on type (these functions are in main.js)
    if (encounterType === 'combat' && typeof showCombatModal === 'function') {
      showCombatModal();
    } else if (encounterType === 'event' && typeof showEventModal === 'function') {
      showEventModal();
    } else if (encounterType === 'shop' && typeof showShopModal === 'function') {
      showShopModal();
    }
  }

  // Always show Finished button (including for amulet game)
  showFinish(n, isAmuletGame);

  // Scroll to keep node vertically centered in viewport
  setTimeout(() => {
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
    // Disable button immediately to prevent multiple clicks
    b.disabled = true;
    b.style.opacity = '0.5';
    b.style.cursor = 'not-allowed';

    // Grey out the Skip button when Finished is pressed
    const skipBtn = node.querySelector('.ability-skip-btn');
    if (skipBtn) {
      skipBtn.disabled = true;
      skipBtn.style.opacity = '0.5';
      skipBtn.style.cursor = 'not-allowed';
      skipBtn.style.background = '#555';
    }

    // Mark this game as finished
    if (typeof markGameFinished === 'function' && gameState && gameState.currentGame) {
      markGameFinished(gameState.currentGame);
    }

    if (isAmuletGame) {
      // Start escape phase
      if (typeof startEscapePhase === 'function') {
        startEscapePhase();
      }
    } else {
      // Show item choice modal first
      if (typeof showItemChoiceModal === 'function') {
        showItemChoiceModal();
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
      z-index: 10;
    `;
    skipBtn.onclick = () => {
      if (confirm('Skip this game and move to the next choice?')) {
        // Disable the Finished button after skipping
        const finishedBtn = node.querySelector('.finish');
        if (finishedBtn) {
          finishedBtn.disabled = true;
          finishedBtn.style.opacity = '0.5';
          finishedBtn.style.cursor = 'not-allowed';
          finishedBtn.style.background = '#555';
        }
        // Disable the Skip button itself
        skipBtn.disabled = true;
        skipBtn.style.opacity = '0.5';
        skipBtn.style.cursor = 'not-allowed';
        skipBtn.style.background = '#555';

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

// ===== STATE RENDERING =====

function renderGameState() {
  console.log('=== RENDERING GAME STATE ===');

  // Clear previous content
  pathContainer.innerHTML = '';
  linesSvg.innerHTML = '';

  // Make sure we have a valid game state
  if (!gameState.currentGame || !gameState.amuletGame) {
    console.error('Invalid game state!', gameState);
    return;
  }

  console.log('Current game:', gameState.currentGame);
  console.log('Amulet game:', gameState.amuletGame);
  console.log('Visited games:', gameState.visitedGames);
  console.log('Character:', gameState.character);
  console.log('PLAYER_CHARACTERS available?', Object.keys(PLAYER_CHARACTERS).length);

  // Update HUD
  document.getElementById('game-health').textContent = `${health}/${maxHealth}`;
  document.getElementById('game-gold').textContent = gold;

  const distance = bfs(gameState.currentGame, gameState.amuletGame.name);
  document.getElementById('distance-display').textContent = `Target: ${gameState.amuletGame.name} — ${distance} steps away`;

  // Recreate arrowhead marker
  createArrowheadMarker();

  // Reconstruct the path from visited games
  const cx = 450;
  let currentY = 120;
  const nodes = [];

  console.log('Creating nodes for', gameState.visitedGames.length, 'games');

  gameState.visitedGames.forEach((gameName, index) => {
    const isLast = index === gameState.visitedGames.length - 1;
    const cls = isLast ? 'current' : 'past';
    const node = addNode(gameName, cls, cx, currentY);
    nodes.push(node);

    if (isLast) {
      gameState.currentY = currentY;
      showFinish(node);

      // Add player icon on current node (above the box)
      if (gameState.character && PLAYER_CHARACTERS[gameState.character]) {
        const playerIcon = document.createElement('img');
        playerIcon.src = PLAYER_CHARACTERS[gameState.character].icon;
        playerIcon.id = 'player-icon';
        playerIcon.style.cssText = `
          position: absolute;
          top: -55px;
          left: 50%;
          transform: translateX(-50%);
          width: 48px;
          height: 48px;
          image-rendering: pixelated;
          z-index: 100;
          animation: playerPulse 2s infinite;
          pointer-events: none;
        `;
        node.appendChild(playerIcon);
      }

      // Dash/Reroll buttons are only shown during game choice selection (via spawnChoices)
      // Skip button is shown with Finished button (via showFinish)
    }

    currentY += 160;
  });

  // Draw lines between consecutive nodes
  for (let i = 0; i < nodes.length - 1; i++) {
    drawPastLine(nodes[i], nodes[i + 1]);
  }

  // Update stats panel
  updateGameStats();
}

// ===== DASH MODAL =====

function showDashModal() {
  if (dash <= 0) return;

  const connections = getGameConnections(gameState.currentGame);

  if (connections.length === 0) {
    alert('No connected games available!');
    return;
  }

  const gamesHTML = connections.map((game, index) => `
    <div class="dash-game-option" data-game="${game}" style="
      padding: 12px 15px;
      margin: 8px 0;
      background: #3a3430;
      border: 2px solid #4a4440;
      border-radius: 6px;
      cursor: pointer;
      transition: all 0.2s;
      color: #e6d5b8;
      font-size: 14px;
    ">
      ${index + 1}. ${game}
    </div>
  `).join('');

  const modal = createGameModal(`
    <div style="text-align: center;">
      <h2 style="color: #66ddff; margin-top: 0;">⚡ Dash to Game</h2>
      <p style="color: #e6d5b8;">Select a connected game to dash to (${connections.length} available)</p>
      <div style="max-height: 400px; overflow-y: auto; margin: 20px 0;">
        ${gamesHTML}
      </div>
      <button onclick="closeGameModal()" style="margin-top: 10px; padding: 10px 20px; background: #555; border: none; color: white; border-radius: 6px; cursor: pointer; font-weight: bold;">
        Cancel
      </button>
    </div>
  `);

  // Add click handlers to game options
  document.querySelectorAll('.dash-game-option').forEach(option => {
    option.onmouseenter = (e) => {
      e.target.style.background = '#4a4440';
      e.target.style.borderColor = '#66ddff';
    };
    option.onmouseleave = (e) => {
      e.target.style.background = '#3a3430';
      e.target.style.borderColor = '#4a4440';
    };
    option.onclick = (e) => {
      const selectedGame = e.target.dataset.game;
      useDash(selectedGame);
      closeGameModal();
    };
  });
}

function useDash(targetGame) {
  if (dash <= 0) return;

  dash--;

  // Clear current choices
  clearChoices();

  // Calculate new position (keep same Y level, centered)
  const y = gameState.currentY;
  const x = 450;

  // Trigger the encounter for this game
  const encounterType = ['combat', 'event', 'shop'][Math.floor(Math.random() * 3)];

  // Advance to the selected game
  advance(targetGame, x, y + 160, encounterType);

  updateGameStats();
  saveCurrentGame();
}

// ===== ABILITY FUNCTIONS =====

function useSkip() {
  if (skip <= 0) return;

  skip--;

  // Track the skipped game (but DON'T mark as finished)
  if (gameState.currentGame && !gameState.skippedGames.includes(gameState.currentGame)) {
    gameState.skippedGames.push(gameState.currentGame);
  }

  // Spawn game choices directly (no item modal, no finish)
  clearChoices();
  spawnChoices();
  updateGameStats();
  saveCurrentGame();
}

function useReroll() {
  if (reroll <= 0) return;

  reroll--;
  clearChoices();
  spawnChoices();
  updateGameStats();
  saveCurrentGame();
}

// Export to global scope
window.initGameplayDOM = initGameplayDOM;
window.bfs = bfs;
window.getGameConnections = getGameConnections;
window.addNode = addNode;
window.showTooltip = showTooltip;
window.moveTooltip = moveTooltip;
window.hideTooltip = hideTooltip;
window.drawArrowLine = drawArrowLine;
window.drawPastLine = drawPastLine;
window.clearChoices = clearChoices;
window.spawnChoices = spawnChoices;
window.advance = advance;
window.showFinish = showFinish;
window.renderGameState = renderGameState;
window.addAbilityButtons = addAbilityButtons;
window.showDashModal = showDashModal;
window.useDash = useDash;
window.useSkip = useSkip;
window.useReroll = useReroll;
