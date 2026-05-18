/**
 * Map layout + rendering.
 *
 * Extracted from js/main.js as part of the Phase 3 decomposition. This
 * file owns the Sugiyama-style layered layout (buildEdgeData, median
 * crossing-minimization, layer reorg, horizontal offsets, amulet pinning),
 * the layered map view used during exploration (generateMapView), the
 * "see whole graph" modal (showMapModal), the SVG arrow renderer
 * (drawMapArrows), tooltip + path-highlight hover state, and zoom.
 *
 * Module-level state (currentMapZoom, markedSvg, originalSvgWidth/Height,
 * playerMarker, amuletMarker) is declared in data.js — these are the
 * legacy bare globals that other modules also touch during save/load.
 *
 * External callers reach map functions through window.* (see exports at
 * the bottom). Inline onclick="zoomMap(...)" / "resetMapZoom()" strings
 * in main.js HTML templates rely on those window bindings.
 *
 * Phase 5 (ESM): the window.* exports go away in favor of named exports.
 */

function getCachedConnections(gameName) {
  if (!connectionCache.has(gameName)) {
    connectionCache.set(gameName, getGameConnections(gameName));
  }
  return connectionCache.get(gameName);
}

// Build edge data structures for efficient graph traversal
function buildEdgeData(layers, gameToLayer) {
  const outgoingEdges = new Map(); // game -> [connected games]
  const incomingEdges = new Map(); // game -> [games that connect to this]

  layers.forEach(layer => {
    layer.forEach(gameData => {
      const gameName = gameData.name || gameData;
      const connections = getCachedConnections(gameName);

      outgoingEdges.set(gameName, []);
      if (!incomingEdges.has(gameName)) {
        incomingEdges.set(gameName, []);
      }

      connections.forEach(targetGame => {
        const targetLayer = gameToLayer.get(targetGame);
        const sourceLayer = gameToLayer.get(gameName);

        // Only consider forward edges (going down the graph)
        if (targetLayer !== undefined && targetLayer > sourceLayer) {
          outgoingEdges.get(gameName).push(targetGame);

          if (!incomingEdges.has(targetGame)) {
            incomingEdges.set(targetGame, []);
          }
          incomingEdges.get(targetGame).push(gameName);
        }
      });
    });
  });

  return { outgoingEdges, incomingEdges };
}

// Calculate median position of connected nodes (Sugiyama median heuristic)
function getMedianPosition(gameName, adjacentLayer, edgeMap, layerPositions) {
  const connectedGames = edgeMap.get(gameName) || [];

  if (connectedGames.length === 0) {
    return layerPositions.get(gameName) || 0;
  }

  // Get positions of connected games in adjacent layer
  const positions = connectedGames
    .map(g => layerPositions.get(g))
    .filter(p => p !== undefined)
    .sort((a, b) => a - b);

  if (positions.length === 0) {
    return layerPositions.get(gameName) || 0;
  }

  // Return median position
  const mid = Math.floor(positions.length / 2);
  if (positions.length % 2 === 0) {
    return (positions[mid - 1] + positions[mid]) / 2;
  } else {
    return positions[mid];
  }
}

// Sugiyama crossing minimization using median heuristic
function minimizeCrossings(layers, gameToLayer, edgeData) {
  const { outgoingEdges, incomingEdges } = edgeData;
  const layerPositions = new Map(); // Track current position of each game in its layer

  // Initialize positions
  layers.forEach((layer, layerIndex) => {
    layer.forEach((gameData, position) => {
      const gameName = gameData.name || gameData;
      layerPositions.set(gameName, position);
    });
  });

  // Perform bi-directional sweeps
  const numIterations = 4;
  for (let iter = 0; iter < numIterations; iter++) {
    // Sweep down (order each layer based on previous layer)
    for (let i = 1; i < layers.length; i++) {
      const currentLayer = layers[i];
      const previousLayer = layers[i - 1];

      // Calculate median position for each game based on incoming edges
      const medianValues = currentLayer.map((gameData, idx) => {
        const gameName = gameData.name || gameData;
        const median = getMedianPosition(gameName, previousLayer, incomingEdges, layerPositions);
        return { gameData, gameName, median, originalIndex: idx };
      });

      // Sort by median position
      medianValues.sort((a, b) => {
        if (a.median !== b.median) {
          return a.median - b.median;
        }
        return a.originalIndex - b.originalIndex; // Stable sort
      });

      // Update layer order and positions
      layers[i] = medianValues.map(v => v.gameData);
      medianValues.forEach((v, newPos) => {
        layerPositions.set(v.gameName, newPos);
      });
    }

    // Sweep up (order each layer based on next layer)
    for (let i = layers.length - 2; i >= 0; i--) {
      const currentLayer = layers[i];
      const nextLayer = layers[i + 1];

      // Calculate median position for each game based on outgoing edges
      const medianValues = currentLayer.map((gameData, idx) => {
        const gameName = gameData.name || gameData;
        const median = getMedianPosition(gameName, nextLayer, outgoingEdges, layerPositions);
        return { gameData, gameName, median, originalIndex: idx };
      });

      // Sort by median position
      medianValues.sort((a, b) => {
        if (a.median !== b.median) {
          return a.median - b.median;
        }
        return a.originalIndex - b.originalIndex; // Stable sort
      });

      // Update layer order and positions
      layers[i] = medianValues.map(v => v.gameData);
      medianValues.forEach((v, newPos) => {
        layerPositions.set(v.gameName, newPos);
      });
    }
  }

  return layers;
}

// Main reorganization function using Sugiyama method
function reorganizeMapLayers(pathData) {
  // Clear connection cache for fresh run
  connectionCache.clear();

  const gameToLayer = new Map();

  // Copy all games to their initial layers (as arrays for ordering)
  const originalLayers = Array.from(pathData.layers.keys()).sort((a, b) => a - b);
  const layers = [];

  originalLayers.forEach(distance => {
    const gamesAtLayer = pathData.layers.get(distance);
    const layerArray = [...gamesAtLayer];
    layers.push(layerArray);

    gamesAtLayer.forEach(gameData => {
      const gameName = gameData.name || gameData;
      gameToLayer.set(gameName, distance);
    });
  });

  // Build edge data structures
  const edgeData = buildEdgeData(layers, gameToLayer);

  // Apply Sugiyama crossing minimization
  const optimizedLayers = minimizeCrossings(layers, gameToLayer, edgeData);

  // Convert back to Map structure for compatibility
  const reorganizedLayers = new Map();
  originalLayers.forEach((distance, index) => {
    reorganizedLayers.set(distance, optimizedLayers[index]);
  });

  return { reorganizedLayers, gameToLayer };
}

// Apply horizontal offsets using improved coordinate assignment
// Based on Brandes-Köpf style algorithm for straight edges
function applyHorizontalOffsets(reorganizedLayers, gameToLayer, pathData) {
  const gameOffsets = new Map();
  const layerKeys = Array.from(reorganizedLayers.keys()).sort((a, b) => a - b);

  // Build edge data for coordinate assignment
  const layers = layerKeys.map(key => reorganizedLayers.get(key));
  const edgeData = buildEdgeData(layers, gameToLayer);
  const { outgoingEdges, incomingEdges } = edgeData;

  // Assign initial coordinates based on layer position
  const coordinates = new Map();
  const minSeparation = 140; // Minimum horizontal separation between nodes

  layers.forEach((layer, layerIndex) => {
    layer.forEach((gameData, position) => {
      const gameName = gameData.name || gameData;
      // Initial coordinate based on position in layer
      coordinates.set(gameName, position * minSeparation);
    });
  });

  // Refine coordinates using median of connected nodes (4 passes)
  for (let pass = 0; pass < 4; pass++) {
    // Downward pass: align with incoming edges
    for (let i = 1; i < layers.length; i++) {
      const currentLayer = layers[i];

      currentLayer.forEach((gameData, idx) => {
        const gameName = gameData.name || gameData;
        const incoming = incomingEdges.get(gameName) || [];

        if (incoming.length > 0) {
          // Get coordinates of incoming nodes
          const incomingCoords = incoming
            .map(g => coordinates.get(g))
            .filter(c => c !== undefined)
            .sort((a, b) => a - b);

          if (incomingCoords.length > 0) {
            // Use median of incoming coordinates
            const mid = Math.floor(incomingCoords.length / 2);
            const medianCoord = incomingCoords.length % 2 === 0
              ? (incomingCoords[mid - 1] + incomingCoords[mid]) / 2
              : incomingCoords[mid];

            coordinates.set(gameName, medianCoord);
          }
        }
      });

      // Resolve conflicts: ensure minimum separation within layer
      const sortedLayer = [...currentLayer]
        .map(gd => ({ name: gd.name || gd, coord: coordinates.get(gd.name || gd) || 0 }))
        .sort((a, b) => a.coord - b.coord);

      let previousCoord = -Infinity;
      sortedLayer.forEach(item => {
        const minCoord = previousCoord + minSeparation;
        if (coordinates.get(item.name) < minCoord) {
          coordinates.set(item.name, minCoord);
        }
        previousCoord = coordinates.get(item.name);
      });
    }

    // Upward pass: align with outgoing edges
    for (let i = layers.length - 2; i >= 0; i--) {
      const currentLayer = layers[i];

      currentLayer.forEach((gameData, idx) => {
        const gameName = gameData.name || gameData;
        const outgoing = outgoingEdges.get(gameName) || [];

        if (outgoing.length > 0) {
          // Get coordinates of outgoing nodes
          const outgoingCoords = outgoing
            .map(g => coordinates.get(g))
            .filter(c => c !== undefined)
            .sort((a, b) => a - b);

          if (outgoingCoords.length > 0) {
            // Use median of outgoing coordinates
            const mid = Math.floor(outgoingCoords.length / 2);
            const medianCoord = outgoingCoords.length % 2 === 0
              ? (outgoingCoords[mid - 1] + outgoingCoords[mid]) / 2
              : outgoingCoords[mid];

            coordinates.set(gameName, medianCoord);
          }
        }
      });

      // Resolve conflicts: ensure minimum separation within layer
      const sortedLayer = [...currentLayer]
        .map(gd => ({ name: gd.name || gd, coord: coordinates.get(gd.name || gd) || 0 }))
        .sort((a, b) => a.coord - b.coord);

      let previousCoord = -Infinity;
      sortedLayer.forEach(item => {
        const minCoord = previousCoord + minSeparation;
        if (coordinates.get(item.name) < minCoord) {
          coordinates.set(item.name, minCoord);
        }
        previousCoord = coordinates.get(item.name);
      });
    }
  }

  // Center the layout: find the middle coordinate and shift to 0
  let minCoord = Infinity;
  let maxCoord = -Infinity;
  coordinates.forEach(coord => {
    minCoord = Math.min(minCoord, coord);
    maxCoord = Math.max(maxCoord, coord);
  });
  const centerOffset = -(minCoord + maxCoord) / 2;

  // Convert absolute coordinates to offsets from center
  coordinates.forEach((coord, gameName) => {
    gameOffsets.set(gameName, coord + centerOffset);
  });

  return gameOffsets;
}

// Ensure amulet game is at the deepest layer
function pushAmuletToBottom(reorganizedLayers, gameToLayer, amuletGame) {
  const amuletLayer = gameToLayer.get(amuletGame);
  if (amuletLayer !== undefined) {
    const maxLayer = Math.max(...Array.from(gameToLayer.values()));

    // If amulet is not already at the deepest layer, move it there
    if (amuletLayer < maxLayer) {
      const currentLayerGames = reorganizedLayers.get(amuletLayer);
      const amuletData = currentLayerGames.find(g => (g.name || g) === amuletGame);

      if (amuletData) {
        // Remove from current layer
        const index = currentLayerGames.indexOf(amuletData);
        currentLayerGames.splice(index, 1);

        // Add to deepest layer
        const newLayer = maxLayer + 1;
        if (!reorganizedLayers.has(newLayer)) {
          reorganizedLayers.set(newLayer, []);
        }
        reorganizedLayers.get(newLayer).push(amuletData);
        gameToLayer.set(amuletGame, newLayer);
      }
    }
  }
}

// Generate map visualization HTML for given distance
function generateMapView(currentGame, amuletGame, maxDistance, precomputedPathData = null) {
  const pathData = precomputedPathData || findPathsUpToDistance(currentGame, amuletGame, maxDistance);
  if (!pathData) return '<p style="color: #888;">No path data available</p>';

  const visitedGames = gameState.visitedGames || [];
  const pastGames = visitedGames.filter(g => g !== currentGame);

  let html = '';

  // Create outer container with padding
  html += '<div style="position: relative; padding: 40px; width: 100%; max-height: 70vh; overflow: auto;">';

  // Container for game boxes - zoom to fit if needed
  html += '<div id="map-game-boxes" style="position: relative; display: flex; flex-direction: column; align-items: center; width: fit-content; min-width: 100%; transform-origin: top center; margin: 0 auto;">';

  // SVG for arrows - as child of game boxes so it scales together
  html += '<svg id="map-arrows" style="position: absolute; top: 0; left: 0; width: 100%; height: 100%; pointer-events: none; z-index: 1; overflow: visible;"></svg>';

  // Show past games first
  if (pastGames.length > 0) {
    html += '<div style="margin-bottom: 30px; padding-bottom: 20px; border-bottom: 2px solid #555;">';
    html += '<h3 style="color: #888; font-size: 14px; margin-bottom: 15px;">Past Journey</h3>';
    html += '<div style="display: flex; flex-direction: column; align-items: center; gap: 5px;">';

    pastGames.forEach((gameName, index) => {
      html += `
        <div style="
          background: #3a3a3a;
          border: 2px solid #555;
          border-radius: 6px;
          padding: 8px 16px;
          font-size: 12px;
          color: #888;
        ">
          ${index + 1}. ${gameName}
        </div>
      `;
      if (index < pastGames.length - 1) {
        html += '<div style="color: #555;">↓</div>';
      }
    });

    html += '</div></div>';
  }

  // Build the layered path visualization
  // Shrink boxes significantly and adjust spacing based on view type
  const shortestDistance = pathData.shortestDistance;
  const isMorePathsView = maxDistance > shortestDistance;

  const boxWidth = 120;  // Reduced from 180
  const boxHeight = 35;  // Reduced from 50
  const horizontalGap = 30;  // Reduced from 40
  const verticalGap = isMorePathsView ? 120 : 80;  // More vertical space for complex view

  let currentY = pastGames.length > 0 ? 50 : 20;

  // Reorganize layers to avoid arrow crossings
  const { reorganizedLayers, gameToLayer } = reorganizeMapLayers(pathData);

  // Ensure amulet game is at the bottom
  pushAmuletToBottom(reorganizedLayers, gameToLayer, amuletGame);

  // Apply horizontal offsets to avoid arrow-box collisions
  const gameOffsets = applyHorizontalOffsets(reorganizedLayers, gameToLayer, pathData);

  // Iterate through reorganized layers
  const layers = Array.from(reorganizedLayers.keys()).sort((a, b) => a - b).filter(layer => reorganizedLayers.get(layer).length > 0);

  layers.forEach((distance, layerIndex) => {
    const gamesAtLayer = reorganizedLayers.get(distance);
    const numGames = gamesAtLayer.length;

    // Calculate total width needed for this layer
    const totalWidth = numGames * boxWidth + (numGames - 1) * horizontalGap;

    html += `<div style="display: flex; justify-content: center; align-items: center; margin-bottom: ${verticalGap}px; position: relative; width: 100%; flex-wrap: nowrap; gap: ${horizontalGap}px;">`;

    gamesAtLayer.forEach((gameData, index) => {
      // gameData is now {name, isOnShortestPath}
      const gameName = gameData.name || gameData; // Handle both old and new format
      const isOnShortestPath = gameData.isOnShortestPath !== undefined ? gameData.isOnShortestPath : true;

      const isCurrentGame = gameName === currentGame;
      const isAmuletGame = gameName === amuletGame;
      const isPastGame = pastGames.includes(gameName);
      const isChoice = !isCurrentGame && !isAmuletGame && !isPastGame &&
        (gameState.currentChoices || []).includes(gameName);

      let boxColor = '#4a4440';
      let borderColor = '#cc6600';

      if (isCurrentGame) {
        boxColor = '#2196F3';
        borderColor = '#4CAF50';
      } else if (isAmuletGame) {
        boxColor = '#cc6600';
        borderColor = 'gold';
      } else if (isPastGame) {
        boxColor = '#3a3a3a';
        borderColor = '#555';
      } else if (isChoice) {
        boxColor = '#3d2d00';
        borderColor = '#ff9900';
      } else if (!isOnShortestPath) {
        // Games NOT on shortest path: dimmed/grayed out
        boxColor = '#2a2a2a';
        borderColor = '#444';
      }

      // Get horizontal offset for this game (if any)
      const horizontalOffset = gameOffsets.get(gameName) || 0;

      // Get encounter icon for this game
      const game = games.find(g => g.name === gameName);
      let encounterIcon = '';
      let encounterColor = '';

      // Get encounter type from gameState (randomly assigned per run)
      const encounterType = gameState.encounterTypes?.[gameName];

      if (game && encounterType && !isCurrentGame && !isAmuletGame && !isPastGame) {
        if (encounterType === 'combat') {
          encounterIcon = '!';
          // Color based on game type
          switch(game.type?.toLowerCase()) {
            case 'action': encounterColor = '#ff4444'; break;
            case 'deckbuilding': encounterColor = '#bb66ff'; break;
            case 'strategy': encounterColor = '#4488ff'; break;
            default: encounterColor = '#44ff44'; break;
          }
        } else if (encounterType === 'event') {
          encounterIcon = '?';
          encounterColor = '#bb66ff';
        } else if (encounterType === 'shop') {
          encounterIcon = '$';
          encounterColor = '#ffd700';
        }
      }

      const choiceAttr = isChoice ? ' data-is-choice="true"' : '';
      const choiceEnterHandler = isChoice
        ? `highlightChoicePath(event, '${gameName.replace(/'/g, "\\'")}'); showMapTooltip(event, '${gameName.replace(/'/g, "\\'")}')`
        : `showMapTooltip(event, '${gameName.replace(/'/g, "\\'")}')`;
      const choiceLeaveHandler = isChoice
        ? `clearChoicePath(); hideMapTooltip()`
        : `hideMapTooltip()`;
      const choiceShadow = isChoice
        ? '0 0 10px rgba(255, 153, 0, 0.6), 0 3px 6px rgba(0,0,0,0.3)'
        : '0 3px 6px rgba(0,0,0,0.3)';
      // Clicking a choice node in the map opens the read-only node detail modal
      const safeGN = gameName.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
      const mapClickHandler = isChoice
        ? `onclick="if(typeof openNodeModalFromMap==='function') openNodeModalFromMap('${safeGN}')"`
        : '';

      // Game-type badge label for map view (replaces the !?$ encounter icons)
      const gameTypeForBadge = game?.type || '';
      const mapTypeColors = { action: '#c0392b', deckbuilding: '#7d3c98', strategy: '#1a6fa0', traditional: '#1e8449' };
      const mapBadgeColor = isAmuletGame ? '#b7950b' : (mapTypeColors[gameTypeForBadge.toLowerCase()] || '#555');
      const mapBadgeLabel = isAmuletGame ? '🏺' : (gameTypeForBadge || '');
      const mapBadgeHTML = (mapBadgeLabel && isChoice)
        ? `<span style="position:absolute;bottom:-9px;left:50%;transform:translateX(-50%);background:${mapBadgeColor};color:white;border-radius:3px;padding:1px 5px;font-size:8px;font-weight:bold;white-space:nowrap;border:1px solid rgba(0,0,0,0.3);pointer-events:none;">${mapBadgeLabel}</span>`
        : '';

      html += `
        <div class="map-game-box-${gameName.replace(/\s+/g, '-')}" data-game="${gameName}"${choiceAttr}
             onmouseenter="${choiceEnterHandler}"
             onmousemove="moveMapTooltip(event)"
             onmouseleave="${choiceLeaveHandler}"
             ${mapClickHandler}
             style="
          background: ${boxColor};
          border: ${isChoice ? '3px' : '2px'} solid ${borderColor};
          border-radius: 6px;
          padding: 6px 10px;
          width: ${boxWidth}px;
          min-height: ${boxHeight}px;
          display: flex;
          align-items: center;
          justify-content: center;
          text-align: center;
          font-weight: bold;
          font-size: 11px;
          color: ${isCurrentGame ? 'white' : (isPastGame || (!isOnShortestPath && !isChoice) ? '#888' : '#e6d5b8')};
          box-shadow: ${choiceShadow};
          cursor: pointer;
          opacity: ${!isOnShortestPath && !isChoice && !isCurrentGame && !isAmuletGame ? '0.5' : '1'};
          transform: translateX(${horizontalOffset}px);
          position: relative;
          margin-bottom: ${isChoice ? '10px' : '0'};
        ">
          ${isCurrentGame ? '📍 ' : ''}${isChoice ? '◆ ' : ''}${gameName}${isAmuletGame ? ' 🏆' : ''}${isOnShortestPath && !isCurrentGame && !isAmuletGame && !isChoice ? ' ⭐' : ''}
          ${mapBadgeHTML}
        </div>
      `;
    });

    html += '</div>';
    currentY += boxHeight + verticalGap;
  });

  html += '</div>'; // Close game boxes container
  html += '</div>'; // Close relative container

  // Add tooltip for hover
  html += '<div id="map-tooltip" style="display: none; position: absolute; background: rgba(30, 30, 30, 0.95); border: 2px solid #cc6600; border-radius: 6px; padding: 10px; z-index: 10000; pointer-events: none; max-width: 350px; font-size: 11px; line-height: 1.4;"></div>';

  return html;
}

// Show map modal with all shortest paths to amulet game
function showMapModal() {
  // Validate game state
  if (!gameState || !gameState.currentGame || !gameState.amuletGame) {
    console.error('Map modal validation failed:', {
      hasGameState: !!gameState,
      hasCurrentGame: !!gameState?.currentGame,
      hasAmuletGame: !!gameState?.amuletGame,
      currentGame: gameState?.currentGame,
      amuletGame: gameState?.amuletGame
    });
    createGameModal('<div style="text-align: center;"><h2>Map Not Available</h2><p>Game state not properly initialized.</p><button onclick="closeGameModal()" style="padding: 10px 20px; margin-top: 20px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer;">Close</button></div>');
    return;
  }

  // currentGame is already a string (game name), not an object
  // amuletGame might be a string or an object depending on how it was set
  const currentGame = typeof gameState.currentGame === 'string' ? gameState.currentGame : gameState.currentGame.name;
  const amuletGame = typeof gameState.amuletGame === 'string' ? gameState.amuletGame : gameState.amuletGame.name;


  // Get shortest path info first
  const shortestPathData = findAllShortestPaths(currentGame, amuletGame);


  let mapHTML = '<div style="text-align: center;">';
  mapHTML += '<h2 style="color: gold; margin-bottom: 20px;">🗺️ Map to Amulet</h2>';

  if (!shortestPathData) {
    mapHTML += '<p style="color: #888;">No path found</p>';
    mapHTML += `<p style="color: #666; font-size: 12px; margin-top: 10px;">From: ${currentGame}<br>To: ${amuletGame}</p>`;
    mapHTML += '<p style="color: #888; font-size: 11px; margin-top: 10px;">The games may not be connected,<br>or you may be at an isolated node.</p>';
  } else {
    const shortestDist = shortestPathData.shortestDistance;

    // Show header with controls at the top
    mapHTML += '<div style="margin-bottom: 20px; padding: 15px; background: rgba(0,0,0,0.3); border-radius: 8px; display: flex; justify-content: space-between; align-items: center; gap: 15px;">';
    mapHTML += `<span style="color: #e6d5b8; font-weight: bold;">Shortest Path: ${shortestDist} steps</span>`;

    // Zoom controls
    mapHTML += `
      <div style="display: flex; align-items: center; gap: 10px;">
        <button onclick="zoomMap(0.8)" style="padding: 5px 10px; background: #555; border: none; border-radius: 4px; color: white; cursor: pointer; font-weight: bold;">-</button>
        <span id="map-zoom-level" style="color: #888; min-width: 50px; text-align: center;">100%</span>
        <button onclick="zoomMap(1.25)" style="padding: 5px 10px; background: #555; border: none; border-radius: 4px; color: white; cursor: pointer; font-weight: bold;">+</button>
        <button onclick="resetMapZoom()" style="padding: 5px 10px; background: #555; border: none; border-radius: 4px; color: white; cursor: pointer; font-size: 10px;">Reset</button>
      </div>
    `;

    mapHTML += `<button onclick="closeGameModal()" style="padding: 8px 20px; background: #555; border: none; border-radius: 6px; color: white; cursor: pointer; font-weight: bold;">Close</button>`;
    mapHTML += '</div>';

    // Show shortest distance view only
    mapHTML += '<div id="map-view-container">';
    mapHTML += generateMapView(currentGame, amuletGame, shortestDist);
    mapHTML += '</div>';

    mapHTML += '</div>';

    createGameModal(mapHTML);

    // Reset zoom level
    currentMapZoom = 1.0;

    // Draw arrows after modal is rendered
    const initialPathData = findPathsUpToDistance(currentGame, amuletGame, shortestDist);
    setTimeout(() => {
      const { gameToLayer } = reorganizeMapLayers(initialPathData);
      drawMapArrows(initialPathData, currentGame, amuletGame, gameToLayer);
    }, 150);
  }
}

// Auto-zoom the map to fit all content within the viewport
function autoZoomMapToFit() {
  const mapContainer = document.getElementById('map-view-container');
  if (!mapContainer) return;

  const modalContent = document.querySelector('.modal-content');
  if (!modalContent) return;

  // Get the game boxes container
  const gameBoxesContainer = document.getElementById('map-game-boxes');
  if (!gameBoxesContainer) return;

  // Get all game boxes to find the total bounds
  const gameBoxes = mapContainer.querySelectorAll('[data-game]');
  if (gameBoxes.length === 0) return;

  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;

  gameBoxes.forEach(box => {
    const rect = box.getBoundingClientRect();
    const containerRect = gameBoxesContainer.getBoundingClientRect();

    const left = rect.left - containerRect.left;
    const right = rect.right - containerRect.left;
    const top = rect.top - containerRect.top;
    const bottom = rect.bottom - containerRect.top;

    minX = Math.min(minX, left);
    maxX = Math.max(maxX, right);
    minY = Math.min(minY, top);
    maxY = Math.max(maxY, bottom);
  });

  const contentWidth = maxX - minX + 160; // Add padding
  const contentHeight = maxY - minY + 160; // Add padding

  // Get available space in modal
  const modalRect = modalContent.getBoundingClientRect();
  const availableWidth = modalRect.width - 60; // Account for padding
  const availableHeight = modalRect.height - 200; // Account for header and padding

  // Calculate scale to fit
  const scaleX = availableWidth / contentWidth;
  const scaleY = availableHeight / contentHeight;
  const scale = Math.min(scaleX, scaleY, 1.0); // Don't zoom in, only zoom out

  if (scale < 1.0) {
    // Apply zoom to the game boxes container
    gameBoxesContainer.style.transform = `scale(${scale})`;
    gameBoxesContainer.setAttribute('data-scale', scale);

    // Adjust container height to account for scaling
    const scaledHeight = contentHeight * scale;
    gameBoxesContainer.parentElement.style.minHeight = scaledHeight + 'px';
  } else {
    gameBoxesContainer.removeAttribute('data-scale');
  }
}

// Draw arrows between games on the map
function drawMapArrows(pathData, currentGame, amuletGame, gameToLayer = null) {
  const svg = document.getElementById('map-arrows');
  if (!svg) {
    console.error('SVG element not found!');
    return;
  }

  // Clear existing arrows
  svg.innerHTML = '';

  // Get parent dimensions and set SVG to fill it completely
  const parentRect = svg.parentElement.getBoundingClientRect();
  svg.setAttribute('width', parentRect.width);
  svg.setAttribute('height', Math.max(parentRect.height, 2000)); // Ensure enough height

  // Create arrowhead marker for shortest path
  const defs = document.createElementNS('http://www.w3.org/2000/svg', 'defs');

  const marker = document.createElementNS('http://www.w3.org/2000/svg', 'marker');
  marker.setAttribute('id', 'map-arrowhead');
  marker.setAttribute('markerWidth', '10');
  marker.setAttribute('markerHeight', '10');
  marker.setAttribute('refX', '9');
  marker.setAttribute('refY', '5');
  marker.setAttribute('orient', 'auto');
  marker.setAttribute('markerUnits', 'userSpaceOnUse');

  const polygon = document.createElementNS('http://www.w3.org/2000/svg', 'polygon');
  polygon.setAttribute('points', '0,0 10,5 0,10');
  polygon.setAttribute('fill', '#4CAF50');
  marker.appendChild(polygon);
  defs.appendChild(marker);
  svg.appendChild(defs);

  // Get all game boxes
  const gameBoxes = document.querySelectorAll('[data-game]');
  const boxPositions = new Map();

  // Get the game boxes container to use as reference
  const gameBoxesContainer = document.getElementById('map-game-boxes');
  const containerRect = gameBoxesContainer ? gameBoxesContainer.getBoundingClientRect() : svg.getBoundingClientRect();

  gameBoxes.forEach(box => {
    const gameName = box.getAttribute('data-game');
    const rect = box.getBoundingClientRect();

    // Calculate position relative to the container (which is the SVG's parent)
    boxPositions.set(gameName, {
      x: rect.left - containerRect.left + rect.width / 2,
      y: rect.top - containerRect.top + rect.height / 2,
      bottom: rect.bottom - containerRect.top,
      top: rect.top - containerRect.top
    });
  });


  // Draw arrows between connected games
  const layers = Array.from(pathData.layers.keys()).sort((a, b) => a - b);

  let arrowsDrawn = 0;

  // Build a flat map of all games in all layers for quick lookup
  const allGamesInMap = new Map();
  const gameDistances = new Map(); // Track which distance each game is at

  // If reorganized layer data is provided, use it; otherwise use original pathData
  if (gameToLayer) {
    // Use the reorganized layer positions
    gameToLayer.forEach((distance, gameName) => {
      gameDistances.set(gameName, distance);
    });
    // Still need to populate allGamesInMap from pathData
    layers.forEach(distance => {
      const gamesAtLayer = pathData.layers.get(distance);
      gamesAtLayer.forEach(gameData => {
        const gameName = gameData.name || gameData;
        allGamesInMap.set(gameName, gameData);
      });
    });
  } else {
    // Use original pathData
    layers.forEach(distance => {
      const gamesAtLayer = pathData.layers.get(distance);
      gamesAtLayer.forEach(gameData => {
        const gameName = gameData.name || gameData;
        allGamesInMap.set(gameName, gameData);
        gameDistances.set(gameName, distance);
      });
    });
  }

  // Track drawn arrows to avoid duplicates
  const drawnArrows = new Set();

  // Collect all vertical arrows for cross-layer connections (only shortest path)
  const arrowsToDrawData = [];

  layers.forEach((distance, layerIndex) => {
    const gamesAtLayer = pathData.layers.get(distance);

    gamesAtLayer.forEach(fromGameData => {
      const fromGame = fromGameData.name || fromGameData;
      const fromIsOnShortestPath = fromGameData.isOnShortestPath !== undefined ? fromGameData.isOnShortestPath : true;
      const fromDistance = distance;

      // Skip if not on shortest path
      if (!fromIsOnShortestPath) return;

      const fromPos = boxPositions.get(fromGame);
      if (!fromPos) {
        return;
      }

      const connections = getGameConnections(fromGame);

      connections.forEach(toGame => {
        const toGameData = allGamesInMap.get(toGame);

        if (toGameData) {
          const toDistance = gameDistances.get(toGame);
          const toIsOnShortestPath = toGameData.isOnShortestPath !== undefined ? toGameData.isOnShortestPath : true;

          // Only draw arrows that are on the shortest path and go forward
          if (!toIsOnShortestPath || toDistance <= fromDistance) {
            return;
          }

          const arrowKey = `${fromGame}->${toGame}`;
          if (drawnArrows.has(arrowKey)) {
            return; // Already drawn this arrow
          }
          drawnArrows.add(arrowKey);

          const toPos = boxPositions.get(toGame);
          if (!toPos) {
            return;
          }

          // Store arrow data for later drawing
          arrowsToDrawData.push({
            fromGame,
            toGame,
            fromPos,
            toPos,
            fromDistance,
            toDistance
          });
        }
      });
    });
  });

  // Draw all shortest path arrows
  arrowsToDrawData.forEach(arrow => {
    const x1 = arrow.fromPos.x;
    const y1 = arrow.fromPos.bottom;
    const x2 = arrow.toPos.x;
    const y2 = arrow.toPos.top;

    // Use straight line for all connections
    const line = document.createElementNS('http://www.w3.org/2000/svg', 'line');
    line.setAttribute('x1', x1);
    line.setAttribute('y1', y1);
    line.setAttribute('x2', x2);
    line.setAttribute('y2', y2);
    line.setAttribute('stroke', '#4CAF50');
    line.setAttribute('stroke-width', '3');
    line.setAttribute('opacity', '0.8');
    line.setAttribute('marker-end', 'url(#map-arrowhead)');
    line.setAttribute('data-from', arrow.fromGame);
    line.setAttribute('data-to', arrow.toGame);
    svg.appendChild(line);

    arrowsDrawn++;
  });
}

// Highlight the shortest path from a choice game to the amulet game on the map.
// Called on mouseenter of a choice node.
function highlightChoicePath(event, choiceGame) {
  const amuletGame = typeof gameState.amuletGame === 'string'
    ? gameState.amuletGame
    : gameState.amuletGame?.name;
  if (!amuletGame) return;

  // Get the path from this choice to the amulet
  const path = bfsPath(choiceGame, amuletGame);
  const pathSet = new Set(path || [choiceGame]);

  // Collect all choice games so we can keep them at full opacity
  const choiceSet = new Set(gameState.currentChoices || []);

  // Dim all map nodes that aren't on this choice's path
  const allNodes = document.querySelectorAll('[data-game]');
  allNodes.forEach(node => {
    const name = node.getAttribute('data-game');
    const isOnPath = pathSet.has(name);
    const isChoice = choiceSet.has(name);
    const isHoveredChoice = name === choiceGame;

    if (isHoveredChoice) {
      node.style.borderColor = '#ffcc00';
      node.style.boxShadow = '0 0 16px rgba(255, 204, 0, 0.9), 0 3px 6px rgba(0,0,0,0.3)';
      node.style.opacity = '1';
    } else if (isOnPath) {
      node.style.borderColor = '#ff9900';
      node.style.boxShadow = '0 0 8px rgba(255, 153, 0, 0.5)';
      node.style.opacity = '1';
    } else if (isChoice) {
      // Other choices: dim slightly
      node.style.opacity = '0.35';
    } else {
      node.style.opacity = '0.25';
    }
  });

  // Highlight arrows on the path, dim others
  const svg = document.getElementById('map-arrows');
  if (svg) {
    svg.querySelectorAll('line').forEach(line => {
      const from = line.getAttribute('data-from');
      const to = line.getAttribute('data-to');
      if (pathSet.has(from) && pathSet.has(to)) {
        line.setAttribute('stroke', '#ffcc00');
        line.setAttribute('stroke-width', '4');
        line.setAttribute('opacity', '1');
      } else {
        line.setAttribute('opacity', '0.1');
      }
    });
  }
}

// Restore all map nodes and arrows to their default appearance.
function clearChoicePath() {
  const allNodes = document.querySelectorAll('[data-game]');
  allNodes.forEach(node => {
    node.style.opacity = '';
    node.style.borderColor = '';
    node.style.boxShadow = '';
  });

  const svg = document.getElementById('map-arrows');
  if (svg) {
    svg.querySelectorAll('line').forEach(line => {
      line.setAttribute('stroke', '#4CAF50');
      line.setAttribute('stroke-width', '3');
      line.setAttribute('opacity', '0.8');
    });
  }
}

// Map tooltip functions
function showMapTooltip(e, gameName) {
  const game = games.find(g => g.name === gameName);
  if (!game) return;

  const tooltip = document.getElementById('map-tooltip');
  if (!tooltip) return;

  // Build connections HTML
  const influences = game.gamesInfluenced ?? [];
  const influencedBy = getInfluencedByGames(gameName);

  let connectionsHTML = '';
  if (influencedBy.length > 0) {
    connectionsHTML += `<div style="margin-top: 8px;"><strong style="color: #4CAF50;">Influenced By:</strong><div style="display: grid; grid-template-columns: 1fr 1fr; gap: 4px; margin-top: 4px;">${influencedBy.map(g => `<span style="background: rgba(76, 175, 80, 0.1); border: 1px solid rgba(76, 175, 80, 0.3); padding: 2px 6px; border-radius: 3px; font-size: 10px; word-wrap: break-word; line-height: 1.3;">${g} → ${gameName}</span>`).join('')}</div></div>`;
  }
  if (influences.length > 0) {
    connectionsHTML += `<div style="margin-top: 8px;"><strong style="color: #9b59b6;">Influences:</strong><div style="display: grid; grid-template-columns: 1fr 1fr; gap: 4px; margin-top: 4px;">${influences.map(g => `<span style="background: rgba(155, 89, 182, 0.1); border: 1px solid rgba(155, 89, 182, 0.3); padding: 2px 6px; border-radius: 3px; font-size: 10px; word-wrap: break-word; line-height: 1.3;">${gameName} → ${g}</span>`).join('')}</div></div>`;
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

  tooltip.innerHTML = `<h4 style="margin: 0 0 8px 0; color: #e6d5b8;">${gameName}</h4>
    <div>Release Year: ${game.year || '—'}</div>
    <div>Type: ${game.type || '—'}</div>
    <div class="mini-map">${connectionsHTML}</div>
    ${tagsHTML}`;

  tooltip.style.display = 'block';
  moveMapTooltip(e);
}

function moveMapTooltip(e) {
  const tooltip = document.getElementById('map-tooltip');
  if (!tooltip) return;

  const offset = 14;
  const tooltipRect = tooltip.getBoundingClientRect();
  const viewportWidth = window.innerWidth;
  const viewportHeight = window.innerHeight;

  // Calculate initial position
  let left = e.clientX + offset;
  let top = e.clientY + offset;

  // Check if tooltip would go off the right edge
  if (left + tooltipRect.width > viewportWidth) {
    left = e.clientX - tooltipRect.width - offset;
  }

  // Check if tooltip would go off the bottom edge
  if (top + tooltipRect.height > viewportHeight) {
    top = e.clientY - tooltipRect.height - offset;
  }

  // Keep tooltip on screen (left edge)
  if (left < 0) {
    left = offset;
  }

  // Keep tooltip on screen (top edge)
  if (top < 0) {
    top = offset;
  }

  tooltip.style.left = left + 'px';
  tooltip.style.top = top + 'px';
}

function hideMapTooltip() {
  const tooltip = document.getElementById('map-tooltip');
  if (tooltip) {
    tooltip.style.display = 'none';
  }
}

// Map zoom functions
let currentMapZoom = 1.0;

function zoomMap(factor) {
  const gameBoxesContainer = document.getElementById('map-game-boxes');
  if (!gameBoxesContainer) return;

  currentMapZoom *= factor;
  currentMapZoom = Math.max(0.25, Math.min(currentMapZoom, 3.0)); // Limit zoom between 25% and 300%

  gameBoxesContainer.style.transform = `scale(${currentMapZoom})`;
  gameBoxesContainer.setAttribute('data-scale', currentMapZoom);

  // Update zoom level display
  const zoomDisplay = document.getElementById('map-zoom-level');
  if (zoomDisplay) {
    zoomDisplay.textContent = Math.round(currentMapZoom * 100) + '%';
  }

  // Adjust container height to account for scaling
  const contentHeight = gameBoxesContainer.scrollHeight;
  const scaledHeight = contentHeight * currentMapZoom;
  gameBoxesContainer.parentElement.style.minHeight = scaledHeight + 'px';
}

function resetMapZoom() {
  currentMapZoom = 1.0;
  const gameBoxesContainer = document.getElementById('map-game-boxes');
  if (!gameBoxesContainer) return;

  gameBoxesContainer.style.transform = 'scale(1.0)';
  gameBoxesContainer.setAttribute('data-scale', '1.0');

  // Update zoom level display
  const zoomDisplay = document.getElementById('map-zoom-level');
  if (zoomDisplay) {
    zoomDisplay.textContent = '100%';
  }

  // Reset container height
  gameBoxesContainer.parentElement.style.minHeight = '';
}

// Make zoom functions globally available
window.zoomMap = zoomMap;
window.resetMapZoom = resetMapZoom;

// Window re-exports for the rest of the map cluster (legacy script-tag model)
if (typeof window !== 'undefined') {
  window.getCachedConnections = getCachedConnections;
  window.buildEdgeData = buildEdgeData;
  window.getMedianPosition = getMedianPosition;
  window.minimizeCrossings = minimizeCrossings;
  window.reorganizeMapLayers = reorganizeMapLayers;
  window.applyHorizontalOffsets = applyHorizontalOffsets;
  window.pushAmuletToBottom = pushAmuletToBottom;
  window.generateMapView = generateMapView;
  window.showMapModal = showMapModal;
  window.autoZoomMapToFit = autoZoomMapToFit;
  window.drawMapArrows = drawMapArrows;
  window.highlightChoicePath = highlightChoicePath;
  window.clearChoicePath = clearChoicePath;
  window.showMapTooltip = showMapTooltip;
  window.moveMapTooltip = moveMapTooltip;
  window.hideMapTooltip = hideMapTooltip;
}
