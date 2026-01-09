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
  console.log('🎨 initGameplayDOM v4.0 - HTML/CSS ARROWS');

  pathContainer = document.getElementById('path-container');
  linesSvg = document.getElementById('connection-lines'); // Keep reference for legacy, but won't use
  tooltip = document.getElementById('game-tooltip');
  viewport = document.getElementById('path-viewport');

  console.log('✅ DOM initialized - using HTML/CSS arrows instead of SVG');
}

// ===== HELPER FUNCTIONS =====

// Get games that influence the specified game
function getInfluencedByGames(gameName) {
  return games
    .filter(g => g.gamesInfluenced?.includes(gameName))
    .map(g => g.name);
}

// Create status icon container for a game node
function createStatusIconContainer(gameName) {
  if (typeof getGameStatuses !== 'function') return null;
  const statuses = getGameStatuses(gameName);
  if (!statuses || statuses.length === 0) return null;

  const container = document.createElement('div');
  container.className = 'status-icon-container';
  container.style.cssText = `
    position: absolute;
    top: -8px;
    left: -8px;
    display: flex;
    gap: 2px;
    z-index: 100;
    pointer-events: none;
  `;

  statuses.forEach((status) => {
    const icon = document.createElement('span');
    icon.textContent = status.icon;
    icon.title = status.name;
    icon.style.cssText = `
      width: 20px;
      height: 20px;
      background: rgba(0, 0, 0, 0.8);
      border: 2px solid #cc6600;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 12px;
      box-shadow: 0 2px 4px rgba(0,0,0,0.5);
    `;
    container.appendChild(icon);
  });

  return container;
}

// Fisher-Yates shuffle algorithm (unbiased)
function shuffleArray(arr) {
  const shuffled = [...arr];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled;
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

// BFS that returns the actual path (array of game names) from start to goal
function bfsPath(start, goal) {
  const queue = [[start, [start]]]; // [current node, path to this node]
  const visited = new Set([start]);

  while (queue.length > 0) {
    const [node, path] = queue.shift();

    if (node === goal) {
      return path;
    }

    const connections = getGameConnections(node);

    connections.forEach(neighbor => {
      if (!visited.has(neighbor)) {
        visited.add(neighbor);
        queue.push([neighbor, [...path, neighbor]]);
      }
    });
  }

  return null; // No path found
}

// Find all games that are on any shortest path from start to goal
// Returns a map of distance -> array of games at that distance
function findAllShortestPaths(start, goal) {
  // First, run BFS from start to get distances from start
  const distFromStart = new Map();
  const queueStart = [[start, 0]];
  const visitedStart = new Set([start]);
  distFromStart.set(start, 0);

  while (queueStart.length > 0) {
    const [node, dist] = queueStart.shift();

    getGameConnections(node).forEach(neighbor => {
      if (!visitedStart.has(neighbor)) {
        visitedStart.add(neighbor);
        distFromStart.set(neighbor, dist + 1);
        queueStart.push([neighbor, dist + 1]);
      }
    });
  }

  // Check if goal is reachable
  if (!distFromStart.has(goal)) {
    return null;
  }

  const shortestDist = distFromStart.get(goal);

  // Now run BFS backwards from goal to get distances to goal
  const distToGoal = new Map();
  const queueGoal = [[goal, 0]];
  const visitedGoal = new Set([goal]);
  distToGoal.set(goal, 0);

  while (queueGoal.length > 0) {
    const [node, dist] = queueGoal.shift();

    // Get reverse connections (games that connect TO this node)
    const reverseConnections = getInfluencedByGames(node);
    // Also check games that this node connects to (bidirectional)
    const game = games.find(g => g.name === node);
    if (game?.gamesInfluenced) {
      reverseConnections.push(...game.gamesInfluenced);
    }

    [...new Set(reverseConnections)].forEach(neighbor => {
      if (!visitedGoal.has(neighbor)) {
        visitedGoal.add(neighbor);
        distToGoal.set(neighbor, dist + 1);
        queueGoal.push([neighbor, dist + 1]);
      }
    });
  }

  // Find all games on shortest paths
  // A game is on a shortest path if distFromStart[game] + distToGoal[game] = shortestDist
  const pathGames = new Map(); // distance from start -> array of games

  distFromStart.forEach((distFrom, gameName) => {
    const distTo = distToGoal.get(gameName);
    if (distTo !== undefined && distFrom + distTo === shortestDist) {
      if (!pathGames.has(distFrom)) {
        pathGames.set(distFrom, []);
      }
      pathGames.get(distFrom).push(gameName);
    }
  });

  return {
    layers: pathGames,
    totalDistance: shortestDist,
    shortestDistance: shortestDist
  };
}

// Find multiple distinct paths from start to goal
// Returns an array of paths, sorted by length (shortest first)
// Each path is an array of game names
function findMultiplePaths(start, goal, maxPaths = 50) {
  const paths = [];
  const maxDepth = 20; // Limit depth to prevent infinite recursion
  let searchCount = 0;
  const maxSearches = 10000; // Prevent infinite loops

  function dfs(current, path, visitedInPath, depth) {
    // Safety checks
    searchCount++;
    if (searchCount > maxSearches) return;
    if (depth > maxDepth) return;
    if (paths.length >= maxPaths) return;

    // If we reached the goal, save this path
    if (current === goal) {
      paths.push([...path]);
      return;
    }

    // Get connections for current game
    const connections = getGameConnections(current);

    // Try each connection
    for (const next of connections) {
      if (!visitedInPath.has(next)) {
        path.push(next);
        visitedInPath.add(next);
        dfs(next, path, visitedInPath, depth + 1);
        path.pop();
        visitedInPath.delete(next);
      }
    }
  }

  // Start DFS from the start node
  try {
    dfs(start, [start], new Set([start]), 0);
  } catch (e) {
    console.error('Error in findMultiplePaths DFS:', e);
  }

  // Sort paths by length (shortest first)
  paths.sort((a, b) => a.length - b.length);

  console.log(`findMultiplePaths: Found ${paths.length} paths after ${searchCount} searches`);

  return paths;
}

// Convert a list of paths into pathData format for map visualization
function pathsToPathData(paths, start, goal) {
  if (!paths || paths.length === 0) return null;

  const shortestDist = paths[0].length - 1; // Subtract 1 because path includes start
  const shortestPathGames = new Set(paths[0]);

  // Organize games into layers by their distance from start
  const layers = new Map();
  const allGamesOnPaths = new Set();

  paths.forEach(path => {
    path.forEach((gameName, index) => {
      allGamesOnPaths.add(gameName);

      if (!layers.has(index)) {
        layers.set(index, []);
      }

      // Add game to this layer if not already there
      const layerGames = layers.get(index);
      if (!layerGames.find(g => g.name === gameName)) {
        layerGames.push({
          name: gameName,
          isOnShortestPath: shortestPathGames.has(gameName)
        });
      }
    });
  });

  return {
    layers: layers,
    totalDistance: Math.max(...Array.from(layers.keys())),
    shortestDistance: shortestDist,
    shortestPathGames: shortestPathGames
  };
}

// Find all games within a certain distance from start to goal
// maxDistance: show paths up to this distance (inclusive)
// Returns both shortest paths and paths up to maxDistance
function findPathsUpToDistance(start, goal, maxDistance) {
  // First, get the shortest paths
  const shortestPathData = findAllShortestPaths(start, goal);
  if (!shortestPathData) return null;

  const shortestDist = shortestPathData.shortestDistance;

  // If maxDistance is less than shortest, just return shortest
  if (maxDistance < shortestDist) {
    maxDistance = shortestDist;
  }

  // Run BFS from start to get all distances
  const distFromStart = new Map();
  const queueStart = [[start, 0]];
  const visitedStart = new Set([start]);
  distFromStart.set(start, 0);

  while (queueStart.length > 0) {
    const [node, dist] = queueStart.shift();

    getGameConnections(node).forEach(neighbor => {
      if (!visitedStart.has(neighbor)) {
        visitedStart.add(neighbor);
        distFromStart.set(neighbor, dist + 1);
        queueStart.push([neighbor, dist + 1]);
      }
    });
  }

  // Run BFS backwards from goal
  const distToGoal = new Map();
  const queueGoal = [[goal, 0]];
  const visitedGoal = new Set([goal]);
  distToGoal.set(goal, 0);

  while (queueGoal.length > 0) {
    const [node, dist] = queueGoal.shift();

    const reverseConnections = getInfluencedByGames(node);
    const game = games.find(g => g.name === node);
    if (game?.gamesInfluenced) {
      reverseConnections.push(...game.gamesInfluenced);
    }

    [...new Set(reverseConnections)].forEach(neighbor => {
      if (!visitedGoal.has(neighbor)) {
        visitedGoal.add(neighbor);
        distToGoal.set(neighbor, dist + 1);
        queueGoal.push([neighbor, dist + 1]);
      }
    });
  }

  // Find all games on paths up to maxDistance
  const pathGames = new Map(); // distance from start -> array of games
  const shortestPathGames = new Set(); // track which games are on shortest path

  distFromStart.forEach((distFrom, gameName) => {
    const distTo = distToGoal.get(gameName);
    if (distTo !== undefined) {
      const totalDist = distFrom + distTo;

      // Mark games on shortest path
      if (totalDist === shortestDist) {
        shortestPathGames.add(gameName);
      }

      // Include games on paths up to maxDistance
      if (totalDist <= maxDistance) {
        if (!pathGames.has(distFrom)) {
          pathGames.set(distFrom, []);
        }
        pathGames.get(distFrom).push({
          name: gameName,
          isOnShortestPath: totalDist === shortestDist
        });
      }
    }
  });

  return {
    layers: pathGames,
    totalDistance: maxDistance,
    shortestDistance: shortestDist,
    shortestPathGames: shortestPathGames
  };
}

function getGameConnections(gameName) {
  const connected = [];

  // Find the game object
  const game = games.find(g => g.name === gameName);

  if (game?.gamesInfluenced) {
    // Add all games this game influences
    connected.push(...game.gamesInfluenced);
  }

  // Find all games that influence this game
  connected.push(...getInfluencedByGames(gameName));

  return [...new Set(connected)]; // Remove duplicates
}

// ===== NODE CREATION =====

function addNode(name, cls, x, y) {
  const d = document.createElement('div');
  d.className = `node ${cls}`;
  d.style.left = x + 'px';
  d.style.top = y + 'px';
  d.textContent = name;

  // Store game name as data attribute for easy access (without button/status text)
  d.dataset.gameName = name;

  // Add status effect icons if the game has any
  const statusContainer = createStatusIconContainer(name);
  if (statusContainer) {
    d.appendChild(statusContainer);
  }

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
  const influences = game.gamesInfluenced ?? []; // Games this game influenced
  const influencedBy = getInfluencedByGames(name); // Games that influenced this game

  // Get main game's cover
  const gameCover = game.coverImage || 'images/covers/no-cover.svg';

  let connectionsHTML = '';
  if (influencedBy.length > 0) {
    connectionsHTML += `
      <div style="margin-top: 10px;">
        <strong style="color: #4CAF50;">Influenced By:</strong>
        <div style="margin-top: 6px; display: grid; grid-template-columns: repeat(3, 1fr); gap: 3px;">
          ${influencedBy.map(g => `
            <div style="
              font-size: 10px;
              padding: 4px 6px;
              background: rgba(76, 175, 80, 0.1);
              border: 1px solid rgba(76, 175, 80, 0.3);
              border-radius: 4px;
              color: #ddd;
              text-align: center;
            ">${g}</div>
          `).join('')}
        </div>
      </div>`;
  }

  if (influences.length > 0) {
    connectionsHTML += `
      <div style="margin-top: 10px;">
        <strong style="color: #9b59b6;">Influenced:</strong>
        <div style="margin-top: 6px; display: grid; grid-template-columns: repeat(3, 1fr); gap: 3px;">
          ${influences.map(g => `
            <div style="
              font-size: 10px;
              padding: 4px 6px;
              background: rgba(155, 89, 182, 0.1);
              border: 1px solid rgba(155, 89, 182, 0.3);
              border-radius: 4px;
              color: #ddd;
              text-align: center;
            ">${g}</div>
          `).join('')}
        </div>
      </div>`;
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

  tooltip.innerHTML = `
    <div style="display: flex; gap: 12px; margin-bottom: 10px;">
      <img
        src="${gameCover}"
        alt="${name}"
        style="
          width: 100px;
          height: 150px;
          object-fit: contain;
          border-radius: 6px;
          background: #1a1a1a;
          flex-shrink: 0;
        "
      />
      <div style="flex: 1; min-width: 0;">
        <h4 style="margin: 0 0 8px 0;">${name}</h4>
        <div>Release Year: ${game.year || '—'}</div>
        <div>Type: ${game.type || '—'}</div>
      </div>
    </div>
    <div class="mini-map">${connectionsHTML}</div>
    ${tagsHTML}`;
  tooltip.style.opacity = 1;
  tooltip.style.display = 'block';
  moveTooltip(e);
}

function moveTooltip(e) {
  const offset = 14;
  const tooltipRect = tooltip.getBoundingClientRect();
  const viewportWidth = window.innerWidth;
  const viewportHeight = window.innerHeight;
  const topBarHeight = 60; // Height of the fixed top bar

  // Calculate initial position
  let left = e.clientX + offset;
  let top = e.clientY + offset;

  // Check if tooltip is too tall for viewport - make it wider to reduce height
  if (tooltipRect.height > viewportHeight - topBarHeight - 40) {
    tooltip.style.width = 'auto';
    tooltip.style.maxWidth = '450px';
  } else {
    tooltip.style.width = '350px';
    tooltip.style.maxWidth = '350px';
  }

  // Re-get rect after potential width change
  const updatedRect = tooltip.getBoundingClientRect();

  // Check if tooltip would go off the right edge
  if (left + updatedRect.width > viewportWidth) {
    left = e.clientX - updatedRect.width - offset;
  }

  // Check if tooltip would go off the left edge
  if (left < 0) {
    left = offset;
  }

  // Check if tooltip would go off the bottom edge
  if (top + updatedRect.height > viewportHeight) {
    top = e.clientY - updatedRect.height - offset;
  }

  // Check if tooltip would go under the top bar
  if (top < topBarHeight) {
    top = topBarHeight + offset;
  }

  // Final safety check - add max-height and scroll if still too tall
  const maxHeight = viewportHeight - topBarHeight - 20;
  if (updatedRect.height > maxHeight) {
    tooltip.style.maxHeight = maxHeight + 'px';
    tooltip.style.overflowY = 'auto';
  } else {
    tooltip.style.maxHeight = 'none';
    tooltip.style.overflowY = 'visible';
  }

  tooltip.style.left = left + 'px';
  tooltip.style.top = top + 'px';
}

function hideTooltip() {
  tooltip.style.opacity = 0;
  setTimeout(() => {
    tooltip.style.display = 'none';
  }, 150);
}

// ===== LINE DRAWING (HTML/CSS) =====

// Helper: Create an HTML/CSS arrow from one point to another
function createCSSArrow(x1, y1, x2, y2, color, width, dashed = false, className = '') {
  const arrow = document.createElement('div');
  arrow.className = `css-arrow ${className}`;

  // Calculate distance and angle
  const dx = x2 - x1;
  const dy = y2 - y1;
  const length = Math.sqrt(dx * dx + dy * dy);
  const angle = Math.atan2(dy, dx) * (180 / Math.PI);

  // Shorten the line so the tip ends exactly at the target point
  const arrowheadSize = 10;
  const shortenedLength = length - arrowheadSize;

  // Position and style the arrow
  arrow.style.position = 'absolute';
  arrow.style.left = x1 + 'px';
  arrow.style.top = y1 + 'px';
  arrow.style.width = shortenedLength + 'px';
  arrow.style.height = width + 'px';
  arrow.style.backgroundColor = color;
  arrow.style.transformOrigin = '0 50%';
  arrow.style.transform = `rotate(${angle}deg)`;
  arrow.style.pointerEvents = 'none';
  arrow.style.zIndex = '0';

  if (dashed) {
    arrow.style.backgroundImage = `repeating-linear-gradient(90deg, ${color} 0px, ${color} 10px, transparent 10px, transparent 15px)`;
    arrow.style.backgroundColor = 'transparent';
  }

  // Add arrowhead at the end of the line (100% position)
  const arrowhead = document.createElement('div');
  arrowhead.style.position = 'absolute';
  arrowhead.style.left = '100%'; // Position at the end of the arrow
  arrowhead.style.top = '50%';
  arrowhead.style.width = '0';
  arrowhead.style.height = '0';
  arrowhead.style.borderLeft = arrowheadSize + 'px solid ' + color;
  arrowhead.style.borderTop = (arrowheadSize * 0.8) + 'px solid transparent';
  arrowhead.style.borderBottom = (arrowheadSize * 0.8) + 'px solid transparent';
  arrowhead.style.transform = 'translateY(-50%)';
  arrow.appendChild(arrowhead);

  return arrow;
}

function drawArrowLine(fromNode, toNode) {
  const r1 = fromNode.getBoundingClientRect();
  const r2 = toNode.getBoundingClientRect();
  const pr = pathContainer.getBoundingClientRect();

  // Calculate start and end points - BOTTOM MIDDLE to TOP MIDDLE
  const x1 = r1.left + r1.width / 2 - pr.left;  // Center X of source
  const y1 = r1.bottom - pr.top;                 // Bottom of source
  const x2 = r2.left + r2.width / 2 - pr.left;   // Center X of target
  const y2 = r2.top - pr.top;                     // Top of target

  // Create HTML/CSS arrow
  const arrow = createCSSArrow(x1, y1, x2, y2, '#ffdd00', 8, true, 'choice-arrow');
  pathContainer.appendChild(arrow);

  console.log(`✅ Choice arrow drawn from (${x1}, ${y1}) to (${x2}, ${y2})`);
}

function drawPastLine(fromNode, toNode) {
  const r1 = fromNode.getBoundingClientRect();
  const r2 = toNode.getBoundingClientRect();
  const pr = pathContainer.getBoundingClientRect();

  const x1 = r1.left + r1.width / 2 - pr.left;
  const y1 = r1.bottom - pr.top;
  const x2 = r2.left + r2.width / 2 - pr.left;
  const y2 = r2.top - pr.top;

  // Create HTML/CSS arrow for past connections
  const arrow = createCSSArrow(x1, y1, x2, y2, '#aaa', 3, false, 'past-arrow');
  arrow.style.opacity = '0.6';
  pathContainer.appendChild(arrow);
}

// Draw all game influence connections as light background arrows
function drawAllGameConnections() {
  console.log('=== drawAllGameConnections() called (HTML/CSS arrows) ===');

  if (!pathContainer) {
    console.error('pathContainer is not defined!');
    return;
  }

  // Get only choice nodes (not past or current nodes)
  // This prevents drawing arrows to past nodes that might have the same game
  const choiceNodes = document.querySelectorAll('.node.choice');
  console.log('Found', choiceNodes.length, 'choice node elements on screen');

  const nodeMap = new Map();

  choiceNodes.forEach(node => {
    // Use data attribute to get clean game name (without button/status text)
    const gameName = node.dataset.gameName;
    if (gameName) {
      nodeMap.set(gameName, node);
    }
  });

  console.log('Total choice nodes mapped:', nodeMap.size);

  // Draw connections for games that have influence relationships
  let connectionsDrawn = 0;

  games.forEach(game => {
    if (game.gamesInfluenced && game.gamesInfluenced.length > 0) {
      const fromNode = nodeMap.get(game.name);

      if (!fromNode) {
        return;
      }

      game.gamesInfluenced.forEach(influencedGame => {
        const toNode = nodeMap.get(influencedGame);

        if (!toNode) {
          return;
        }

        // Draw a subtle background arrow (pointing FROM influenced game TO influencing game - upward)
        const r1 = fromNode.getBoundingClientRect();
        const r2 = toNode.getBoundingClientRect();
        const pr = pathContainer.getBoundingClientRect();

        const x1 = r2.left + r2.width / 2 - pr.left;  // Start from influenced game (bottom)
        const y1 = r2.bottom - pr.top;
        const x2 = r1.left + r1.width / 2 - pr.left;  // Point to influencing game (top)
        const y2 = r1.top - pr.top;

        // Create subtle gray background arrow
        const arrow = createCSSArrow(x1, y1, x2, y2, 'rgba(100, 100, 100, 0.3)', 2, false, 'background-connection');
        pathContainer.appendChild(arrow);
        connectionsDrawn++;

        console.log(`  ✓ Arrow: "${game.name}" → "${influencedGame}"`);
      });
    }
  });

  console.log(`=== Drew ${connectionsDrawn} background connection arrows ===`);
}

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
      console.log(`Adding portal connections: ${portalGames.join(', ')}`);
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

    // Get encounter type from game data (pre-determined at map generation)
    let encounterType, encounterIcon, encounterColor;

    // Find the game object
    const game = games.find(game => game.name === g);

    if (game && game.encounterType) {
      // Use pre-determined encounter type from game data
      encounterType = game.encounterType;

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
    console.log('🎯 spawnChoices: requestAnimationFrame callback executing');

    // Draw background connection arrows (gray) for all game connections
    drawAllGameConnections();

    // Draw choice arrows
    const currentNode = document.querySelector('.node.current');
    const choiceNodes = document.querySelectorAll('.node.choice');

    console.log(`Drawing arrows: current node exists = ${!!currentNode}, choice nodes = ${choiceNodes.length}`);

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
  const difficulty = gameState.finishedGames?.length || 0;
  document.getElementById('distance-display').textContent = `Target: ${gameState.amuletGame.name} — ${distance} steps away | Difficulty: ${difficulty}`;

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
    // Store the encounter type for later
    gameState.nextEncounterType = encounterType;

    // Regeneration trait: Every time you choose a game whose encounter isn't enemy combat, heal +1
    if (encounterType !== 'combat' && typeof hasTrait === 'function' && hasTrait('regeneration')) {
      health = Math.min(health + 1, maxHealth);
      gameState.health = health;
      console.log('Regeneration trait triggered: +1 Health');
      if (typeof updateTopBar === 'function') {
        updateTopBar();
      }
    }

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

  // Update verification curses display when entering gameplay phase
  if (typeof updateVerificationCursesDisplay === 'function') {
    updateVerificationCursesDisplay();
  }

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
    // Remove both buttons from DOM
    const skipBtn = node.querySelector('.ability-skip-btn');
    if (skipBtn) {
      skipBtn.remove();
    }
    b.remove();

    if (isAmuletGame) {
      // Mark game as finished first
      if (typeof markGameFinished === 'function' && gameState && gameState.currentGame) {
        markGameFinished(gameState.currentGame);
      }
      // Start escape phase
      if (typeof startEscapePhase === 'function') {
        startEscapePhase();
      }
    } else {
      // Show curse verification FIRST, then Precision Landing verification, then mark finished, then item choice
      if (typeof showCurseVerificationModal === 'function') {
        showCurseVerificationModal(() => {
          // After curse verification, check for Precision Landing trait
          if (typeof showPerfectGameVerificationModal === 'function') {
            showPerfectGameVerificationModal(() => {
              // After Precision Landing verification, mark game as finished
              if (typeof markGameFinished === 'function' && gameState && gameState.currentGame) {
                markGameFinished(gameState.currentGame);
              }

              // Check if we're in the middle of the Colosseum event
              if (gameState.colosseumState && gameState.colosseumState.stage === 'first_fight') {
                // Show item choice first, then Colosseum choices
                if (typeof showItemChoiceModal === 'function') {
                  showItemChoiceModal(() => {
                    // After item selection, update stage and show Colosseum choices
                    gameState.colosseumState.stage = 'choice';
                    if (typeof showColosseumChoices === 'function') {
                      showColosseumChoices();
                    }
                  });
                }
              } else if (gameState.colosseumState && gameState.colosseumState.stage === 'champion') {
                // Show item choice first, then ask about attempts
                if (typeof showItemChoiceModal === 'function') {
                  showItemChoiceModal(() => {
                    // After item selection, ask if it took 3 or less attempts
                    if (typeof handleChampionResult === 'function') {
                      handleChampionResult();
                    }
                  });
                }
              } else {
                // Normal flow - show item choice
                if (typeof showItemChoiceModal === 'function') {
                  showItemChoiceModal();
                }
              }
            });
          } else {
            // Fallback if Precision Landing verification not available
            if (typeof markGameFinished === 'function' && gameState && gameState.currentGame) {
              markGameFinished(gameState.currentGame);
            }

            // Check if we're in the middle of the Colosseum event
            if (gameState.colosseumState && gameState.colosseumState.stage === 'first_fight') {
              // Show item choice first, then Colosseum choices
              if (typeof showItemChoiceModal === 'function') {
                showItemChoiceModal(() => {
                  // After item selection, update stage and show Colosseum choices
                  gameState.colosseumState.stage = 'choice';
                  if (typeof showColosseumChoices === 'function') {
                    showColosseumChoices();
                  }
                });
              }
            } else if (gameState.colosseumState && gameState.colosseumState.stage === 'champion') {
              // Show item choice first, then ask about attempts
              if (typeof showItemChoiceModal === 'function') {
                showItemChoiceModal(() => {
                  // After item selection, ask if it took 3 or less attempts
                  if (typeof handleChampionResult === 'function') {
                    handleChampionResult();
                  }
                });
              }
            } else {
              // Normal flow - show item choice
              if (typeof showItemChoiceModal === 'function') {
                showItemChoiceModal();
              }
            }
          }
        });
      } else {
        // Fallback if verification not available
        if (typeof markGameFinished === 'function' && gameState && gameState.currentGame) {
          markGameFinished(gameState.currentGame);
        }

        // Check if we're in the middle of the Colosseum event
        if (gameState.colosseumState && gameState.colosseumState.stage === 'first_fight') {
          // Show item choice first, then Colosseum choices
          if (typeof showItemChoiceModal === 'function') {
            showItemChoiceModal(() => {
              // After item selection, update stage and show Colosseum choices
              gameState.colosseumState.stage = 'choice';
              if (typeof showColosseumChoices === 'function') {
                showColosseumChoices();
              }
            });
          }
        } else if (gameState.colosseumState && gameState.colosseumState.stage === 'champion') {
          // Show item choice first, then ask about attempts
          if (typeof showItemChoiceModal === 'function') {
            showItemChoiceModal(() => {
              // After item selection, ask if it took 3 or less attempts
              if (typeof handleChampionResult === 'function') {
                handleChampionResult();
              }
            });
          }
        } else {
          // Normal flow - show item choice
          if (typeof showItemChoiceModal === 'function') {
            showItemChoiceModal();
          }
        }
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

  const distance = bfsCached(gameState.currentGame, gameState.amuletGame.name);
  const difficulty = gameState.finishedGames?.length || 0;
  document.getElementById('distance-display').textContent = `Target: ${gameState.amuletGame.name} — ${distance} steps away | Difficulty: ${difficulty}`;

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
          top: -70px;
          left: 50%;
          transform: translateX(-50%);
          max-width: 80px;
          max-height: 80px;
          min-width: 56px;
          min-height: 56px;
          object-fit: contain;
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

  // Background connection arrows removed from game screen (looks off-putting)

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

  // Sort connections alphabetically
  const sortedConnections = [...connections].sort((a, b) => a.localeCompare(b));

  const gamesHTML = sortedConnections.map((game) => `
    <div class="dash-game-option" data-game="${game}" style="
      padding: 12px 15px;
      background: #3a3430;
      border: 2px solid #4a4440;
      border-radius: 6px;
      cursor: pointer;
      transition: all 0.2s;
      color: #e6d5b8;
      font-size: 14px;
      text-align: center;
    ">
      ${game}
    </div>
  `).join('');

  const modal = createGameModal(`
    <div style="text-align: center;">
      <h2 style="color: #66ddff; margin-top: 0;">⚡ Dash to Game</h2>
      <p style="color: #e6d5b8;">Select a connected game to dash to (${connections.length} available)</p>
      <div style="max-height: 500px; overflow-y: auto; margin: 20px 0; padding: 10px;">
        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 10px;">
          ${gamesHTML}
        </div>
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

  // Get the pre-determined encounter type for this game
  const game = games.find(g => g.name === targetGame);
  const encounterType = (game && game.encounterType) ? game.encounterType : 'combat';

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

// ===== STATUS ICON REFRESH =====

/**
 * Update status icons on a specific node or all nodes
 * @param {HTMLElement|null} node - Specific node to update, or null to update all nodes
 */
function updateNodeStatusIcons(node = null) {
  const nodesToUpdate = node ? [node] : document.querySelectorAll('.node');

  nodesToUpdate.forEach(nodeEl => {
    // Get the game name from the node's text content
    const gameName = nodeEl.textContent.replace(/[^\w\s:'-]/g, '').trim();

    // Remove existing status container
    const existingContainer = nodeEl.querySelector('.status-icon-container');
    if (existingContainer) {
      existingContainer.remove();
    }

    // Add new status icons if the game has any
    const statusContainer = createStatusIconContainer(gameName);
    if (statusContainer) {
      // Insert at the beginning of the node
      nodeEl.insertBefore(statusContainer, nodeEl.firstChild);
    }
  });
}

// Export to global scope
window.initGameplayDOM = initGameplayDOM;
window.bfs = bfs;
window.bfsPath = bfsPath;
window.findAllShortestPaths = findAllShortestPaths;
window.findMultiplePaths = findMultiplePaths;
window.pathsToPathData = pathsToPathData;
window.getGameConnections = getGameConnections;
window.getInfluencedByGames = getInfluencedByGames;
window.addNode = addNode;
window.showTooltip = showTooltip;
window.moveTooltip = moveTooltip;
window.hideTooltip = hideTooltip;
window.drawArrowLine = drawArrowLine;
window.drawPastLine = drawPastLine;
window.clearChoices = clearChoices;
window.clearAllArrows = clearAllArrows;
window.spawnChoices = spawnChoices;
window.advance = advance;
window.showFinish = showFinish;
window.renderGameState = renderGameState;
window.showDashModal = showDashModal;
window.useDash = useDash;
window.useSkip = useSkip;
window.useReroll = useReroll;
window.updateNodeStatusIcons = updateNodeStatusIcons;
