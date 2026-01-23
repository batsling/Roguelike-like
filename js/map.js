// ===== MAP.JS - SVG Map Viewer with Pan/Zoom =====
//
// This module handles:
// - SVG file loading and rendering
// - Pan and zoom controls
// - Player and amulet marker placement
// - Box highlighting for games
// - SVG saving

// ===== MAP STATE =====
// These are defined in data.js but we reference them here

// ===== UTILITY FUNCTIONS =====

function updateTransform() {
  const svgElement = document.getElementById('svg-viewport').querySelector('svg');
  if (svgElement) {
    svgElement.style.transform = `translate(${translateX}px, ${translateY}px) scale(${scale})`;
  }
}

function updateZoomSlider() {
  const slider = document.getElementById('zoom-slider');
  const zoomValue = document.getElementById('zoom-value');
  if (slider && zoomValue) {
    slider.value = scale * 100;
    zoomValue.textContent = Math.round(scale * 100) + '%';
  }
}

function zoom(factor, centerX, centerY) {
  const newScale = Math.max(0.1, Math.min(5, scale * factor));

  if (centerX !== undefined && centerY !== undefined) {
    // Zoom towards a specific point
    translateX = centerX - (centerX - translateX) * (newScale / scale);
    translateY = centerY - (centerY - translateY) * (newScale / scale);
  }

  scale = newScale;
  updateTransform();
  updateZoomSlider();
}

function resetView() {
  scale = 1;
  translateX = 0;
  translateY = 0;
  updateTransform();
  updateZoomSlider();
}

// ===== MARKER MANAGEMENT =====

function setupMarkerDragging() {
  let draggingMarker = null;
  let offsetX, offsetY;

  const svgElement = document.getElementById('svg-viewport').querySelector('svg');
  if (!svgElement) return;

  svgElement.addEventListener('mousedown', (e) => {
    if (e.target.classList.contains('movable-marker')) {
      draggingMarker = e.target;
      const rect = svgElement.getBoundingClientRect();
      offsetX = (e.clientX - rect.left) / scale - parseFloat(draggingMarker.getAttribute('x'));
      offsetY = (e.clientY - rect.top) / scale - parseFloat(draggingMarker.getAttribute('y'));
      e.preventDefault();
    }
  });

  svgElement.addEventListener('mousemove', (e) => {
    if (draggingMarker) {
      const rect = svgElement.getBoundingClientRect();
      const x = (e.clientX - rect.left) / scale - offsetX;
      const y = (e.clientY - rect.top) / scale - offsetY;
      draggingMarker.setAttribute('x', x);
      draggingMarker.setAttribute('y', y);
      e.preventDefault();
    }
  });

  svgElement.addEventListener('mouseup', () => {
    draggingMarker = null;
  });
}

function addPlayerAndAmuletMarkers() {
  const svgElement = document.getElementById('svg-viewport').querySelector('svg');
  if (!svgElement) {
    alert('Please load an SVG first');
    return;
  }

  // Remove existing markers if any
  if (playerMarker) playerMarker.remove();
  if (amuletMarker) amuletMarker.remove();

  // Create player marker
  playerMarker = document.createElementNS('http://www.w3.org/2000/svg', 'image');
  playerMarker.setAttribute('href', playerImageUrl);
  playerMarker.setAttribute('width', '64');
  playerMarker.setAttribute('height', '64');
  playerMarker.setAttribute('x', '50');
  playerMarker.setAttribute('y', '50');
  playerMarker.setAttribute('class', 'movable-marker');
  playerMarker.dataset.type = 'player';
  playerMarker.style.cursor = 'move';

  // Create amulet marker
  amuletMarker = document.createElementNS('http://www.w3.org/2000/svg', 'image');
  amuletMarker.setAttribute('href', amuletImageUrl);
  amuletMarker.setAttribute('width', '64');
  amuletMarker.setAttribute('height', '64');
  amuletMarker.setAttribute('x', '150');
  amuletMarker.setAttribute('y', '50');
  amuletMarker.setAttribute('class', 'movable-marker');
  amuletMarker.dataset.type = 'amulet';
  amuletMarker.style.cursor = 'move';

  svgElement.appendChild(playerMarker);
  svgElement.appendChild(amuletMarker);

  setupMarkerDragging();
}

// ===== GAME BOX MARKING =====

function markGamesOnMap() {
  const svgElement = document.getElementById('svg-viewport').querySelector('svg');
  if (!svgElement) {
    alert('Please load an SVG first');
    return;
  }

  if (games.length === 0) {
    alert('Please load game data first (upload Excel file)');
    return;
  }

  const texts = svgElement.querySelectorAll('text');
  let matchCount = 0;

  texts.forEach(text => {
    const textContent = text.textContent.trim();
    const matchedGame = games.find(game => game.name === textContent);

    if (matchedGame) {
      // Get text position and add visual indicator
      const bbox = text.getBBox();

      // Add a highlight circle
      const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
      circle.setAttribute('cx', bbox.x + bbox.width / 2);
      circle.setAttribute('cy', bbox.y + bbox.height / 2);
      circle.setAttribute('r', '8');
      circle.setAttribute('fill', matchedGame.connected ? '#4CAF50' : '#ff4444');
      circle.setAttribute('opacity', '0.7');
      circle.setAttribute('class', 'game-mark');

      text.parentElement.insertBefore(circle, text);
      matchCount++;
    }
  });

  document.getElementById('boxCount').textContent = `Games marked: ${matchCount}`;
  document.getElementById('map-status').textContent = `Marked ${matchCount} games on map`;
}

function toggleDebugHighlights() {
  debugMode = !debugMode;
  const svgElement = document.getElementById('svg-viewport').querySelector('svg');
  if (!svgElement) return;

  const rects = svgElement.querySelectorAll('rect');
  rects.forEach(rect => {
    if (debugMode) {
      rect.classList.add('highlight');
    } else {
      rect.classList.remove('highlight');
    }
  });
}

// ===== SVG SAVING =====

function saveMarkedSVG() {
  const svgElement = document.getElementById('svg-viewport').querySelector('svg');
  if (!svgElement) {
    alert('No SVG loaded');
    return;
  }

  const svgData = new XMLSerializer().serializeToString(svgElement);
  const blob = new Blob([svgData], { type: 'image/svg+xml' });
  const url = URL.createObjectURL(blob);

  const a = document.createElement('a');
  a.href = url;
  a.download = 'marked-map.svg';
  a.click();

  URL.revokeObjectURL(url);
}

// Export to global scope
window.updateTransform = updateTransform;
window.updateZoomSlider = updateZoomSlider;
window.zoom = zoom;
window.resetView = resetView;
window.setupMarkerDragging = setupMarkerDragging;
window.addPlayerAndAmuletMarkers = addPlayerAndAmuletMarkers;
window.markGamesOnMap = markGamesOnMap;
window.toggleDebugHighlights = toggleDebugHighlights;
window.saveMarkedSVG = saveMarkedSVG;
