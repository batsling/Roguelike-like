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
  connections.forEach(connection => {
    if (connection.influencer === gameName) {
      connected.push(connection.influencee);
    }
    if (connection.influencee === gameName) {
      connected.push(connection.influencer);
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
  const influences = []; // Games this game influenced
  const influencedBy = []; // Games that influenced this game

  connections.forEach(connection => {
    if (connection.influencer === name) {
      influences.push(connection.influencee);
    }
    if (connection.influencee === name) {
      influencedBy.push(connection.influencer);
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

  tooltip.innerHTML = `<h4>${name}</h4>
    <div>Release Year: ${game.year || '—'}</div>
    <div>Type: ${game.type || '—'}</div>
    <div class="mini-map">${connectionsHTML}</div>`;
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
  l.setAttribute('stroke', 'gold');
  l.setAttribute('stroke-width', '4');
  l.setAttribute('opacity', '0.8');
  l.setAttribute('marker-end', 'url(#arrowhead)');
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
  polygon.setAttribute('fill', 'gold');

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

  // Get all connected games
  const allConnections = getGameConnections(gameState.currentGame);

  // Allow all connections (games can be repeated)
  const gamesToChooseFrom = allConnections;

  // Randomly shuffle and take 3
  const shuffled = [...gamesToChooseFrom].sort(() => Math.random() - 0.5);
  const opts = shuffled.slice(0, Math.min(3, shuffled.length));

  // Increased spacing to prevent overlap with icons (320px apart)
  const spacing = 320;
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

    // Draw arrow line from current to this choice
    if (currentNode) {
      drawArrowLine(currentNode, n);
    }

    n.onclick = () => advance(g, nx, ny, encounterType);
  });
}

// ===== GAME ADVANCEMENT =====

function advance(game, x, y, encounterType) {
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

  // Smooth scroll to new position
  setTimeout(() => {
    viewport.scrollTo({
      top: y - 200,
      behavior: 'smooth'
    });
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
}

// ===== STATE RENDERING =====

function renderGameState() {
  // Clear previous content
  pathContainer.innerHTML = '';
  linesSvg.innerHTML = '';

  // Make sure we have a valid game state
  if (!gameState.currentGame || !gameState.amuletGame) {
    console.error('Invalid game state', gameState);
    return;
  }

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

  console.log('Rendering games:', gameState.visitedGames);

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
