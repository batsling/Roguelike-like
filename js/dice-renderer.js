/**
 * 3D Dice Renderer
 * Renders and animates 3D dice using Three.js
 * Supports D20 with customizable face textures
 */

// Three.js scene, camera, renderer
let diceScene = null;
let diceCamera = null;
let diceRenderer = null;
let diceMesh = null;
let diceContainer = null;
let isRolling = false;
let rollCallback = null;

/**
 * Initialize the 3D dice renderer
 * @param {HTMLElement} container - DOM element to render into
 */
function initDiceRenderer(container) {
  diceContainer = container;

  // Create scene
  diceScene = new THREE.Scene();
  diceScene.background = new THREE.Color(0x1a1410);

  // Create camera
  const width = container.clientWidth;
  const height = container.clientHeight;
  diceCamera = new THREE.PerspectiveCamera(50, width / height, 0.1, 1000);
  diceCamera.position.z = 5;

  // Create renderer
  diceRenderer = new THREE.WebGLRenderer({ antialias: true });
  diceRenderer.setSize(width, height);
  container.appendChild(diceRenderer.domElement);

  // Add lights
  const ambientLight = new THREE.AmbientLight(0xffffff, 0.6);
  diceScene.add(ambientLight);

  const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
  directionalLight.position.set(5, 5, 5);
  diceScene.add(directionalLight);

  // Start render loop
  animate();
}

/**
 * Create canvas texture for a dice face with a number
 * @param {number} number - Number to display on face
 * @param {Object} side - Side data from dice system (optional)
 * @returns {THREE.CanvasTexture} Texture for the face
 */
function createFaceTexture(number, side = null) {
  const canvas = document.createElement('canvas');
  canvas.width = 128;
  canvas.height = 128;
  const ctx = canvas.getContext('2d');

  // Background
  ctx.fillStyle = '#cc6600';
  ctx.fillRect(0, 0, 128, 128);

  // Border
  ctx.strokeStyle = '#000000';
  ctx.lineWidth = 4;
  ctx.strokeRect(0, 0, 128, 128);

  // If side has a custom texture, use it
  if (side && side.texture) {
    // Load custom texture (future feature)
    // For now, just draw the number
  }

  // Number
  const displayValue = side && side.displayValue !== null ? side.displayValue : number;
  ctx.fillStyle = '#ffffff';
  ctx.font = 'bold 72px Arial';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(displayValue.toString(), 64, 64);

  const texture = new THREE.CanvasTexture(canvas);
  texture.needsUpdate = true;
  return texture;
}

/**
 * Create a D20 mesh with numbered faces
 * @param {Object} diceData - Dice data from dice system
 * @returns {THREE.Mesh} D20 mesh
 */
function createD20Mesh(diceData) {
  // Create icosahedron geometry (20 faces)
  const geometry = new THREE.IcosahedronGeometry(1, 0);

  // Create materials for each face
  const materials = [];

  // D20 face numbering mapping (icosahedron face index to D20 number)
  // This mapping ensures opposite faces sum to 21
  const faceNumberMap = [
    1, 20, 2, 19, 3, 18, 4, 17, 5, 16,
    6, 15, 7, 14, 8, 13, 9, 12, 10, 11
  ];

  // Create a material for each face
  for (let i = 0; i < 20; i++) {
    const number = faceNumberMap[i];
    const sideIndex = number - 1; // Convert to 0-based index
    const side = diceData.sides[sideIndex];
    const texture = createFaceTexture(number, side);

    const material = new THREE.MeshStandardMaterial({
      map: texture,
      roughness: 0.5,
      metalness: 0.1
    });

    materials.push(material);
  }

  // Assign materials to faces
  const mesh = new THREE.Mesh(geometry, materials);

  // Set face materials
  for (let i = 0; i < geometry.attributes.position.count; i += 3) {
    const faceIndex = Math.floor(i / 3);
    if (faceIndex < 20) {
      geometry.addGroup(i, 3, faceIndex);
    }
  }

  return mesh;
}

/**
 * Create and add a dice to the scene
 * @param {Object} diceData - Dice data from dice system
 */
function createDice(diceData) {
  // Remove old dice if it exists
  if (diceMesh) {
    diceScene.remove(diceMesh);
    diceMesh.geometry.dispose();
    diceMesh.material.forEach(mat => {
      if (mat.map) mat.map.dispose();
      mat.dispose();
    });
  }

  // Create new dice
  diceMesh = createD20Mesh(diceData);
  diceScene.add(diceMesh);
}

/**
 * Roll the dice with animation
 * @param {Object} diceData - Dice data from dice system
 * @param {number} result - Pre-determined result from dice system
 * @param {Function} callback - Callback when roll completes
 */
function rollDice(diceData, result, callback) {
  if (isRolling) {
    console.warn('Dice is already rolling');
    return;
  }

  isRolling = true;
  rollCallback = callback;

  // Random rotation for animation
  const rotationSpeed = {
    x: (Math.random() - 0.5) * 0.3,
    y: (Math.random() - 0.5) * 0.3,
    z: (Math.random() - 0.5) * 0.3
  };

  // Animation duration (1.5 seconds)
  const duration = 1500;
  const startTime = Date.now();

  // Face number to rotation mapping
  const faceRotations = getFaceRotations();
  const targetRotation = faceRotations[result - 1]; // Convert to 0-based index

  function animateRoll() {
    const elapsed = Date.now() - startTime;
    const progress = Math.min(elapsed / duration, 1);

    if (progress < 1) {
      // Spinning phase
      diceMesh.rotation.x += rotationSpeed.x;
      diceMesh.rotation.y += rotationSpeed.y;
      diceMesh.rotation.z += rotationSpeed.z;

      // Ease out as we approach the end
      const easeOut = 1 - Math.pow(1 - progress, 3);

      requestAnimationFrame(animateRoll);
    } else {
      // Final position - orient to show the result face
      diceMesh.rotation.set(targetRotation.x, targetRotation.y, targetRotation.z);

      isRolling = false;

      if (rollCallback) {
        rollCallback(result);
        rollCallback = null;
      }
    }
  }

  // Start roll animation with a jump
  animateDiceJump(() => {
    animateRoll();
  });
}

/**
 * Animate dice jumping up before rolling
 * @param {Function} callback - Callback when jump completes
 */
function animateDiceJump(callback) {
  const jumpHeight = 1.5;
  const jumpDuration = 300;
  const startY = diceMesh.position.y;
  const startTime = Date.now();

  function jump() {
    const elapsed = Date.now() - startTime;
    const progress = Math.min(elapsed / jumpDuration, 1);

    if (progress < 0.5) {
      // Jump up
      diceMesh.position.y = startY + (jumpHeight * (progress * 2));
    } else {
      // Fall down
      diceMesh.position.y = startY + (jumpHeight * (1 - (progress - 0.5) * 2));
    }

    if (progress < 1) {
      requestAnimationFrame(jump);
    } else {
      diceMesh.position.y = startY;
      callback();
    }
  }

  jump();
}

/**
 * Get rotation values for each D20 face to show it on top
 * @returns {Array<Object>} Array of rotation objects for each face
 */
function getFaceRotations() {
  // Pre-calculated rotations to show each face of a D20 on top
  // These are approximate and may need fine-tuning
  return [
    { x: 0, y: 0, z: 0 },                           // 1
    { x: Math.PI, y: 0, z: 0 },                     // 2
    { x: Math.PI / 2, y: 0, z: 0 },                 // 3
    { x: -Math.PI / 2, y: 0, z: 0 },                // 4
    { x: 0, y: Math.PI / 2, z: 0 },                 // 5
    { x: 0, y: -Math.PI / 2, z: 0 },                // 6
    { x: Math.PI / 3, y: 0, z: 0 },                 // 7
    { x: -Math.PI / 3, y: 0, z: 0 },                // 8
    { x: 2 * Math.PI / 3, y: 0, z: 0 },             // 9
    { x: -2 * Math.PI / 3, y: 0, z: 0 },            // 10
    { x: 0, y: Math.PI / 3, z: 0 },                 // 11
    { x: 0, y: -Math.PI / 3, z: 0 },                // 12
    { x: 0, y: 2 * Math.PI / 3, z: 0 },             // 13
    { x: 0, y: -2 * Math.PI / 3, z: 0 },            // 14
    { x: Math.PI / 4, y: Math.PI / 4, z: 0 },       // 15
    { x: -Math.PI / 4, y: Math.PI / 4, z: 0 },      // 16
    { x: Math.PI / 4, y: -Math.PI / 4, z: 0 },      // 17
    { x: -Math.PI / 4, y: -Math.PI / 4, z: 0 },     // 18
    { x: 3 * Math.PI / 4, y: Math.PI / 4, z: 0 },   // 19
    { x: -3 * Math.PI / 4, y: Math.PI / 4, z: 0 }   // 20
  ];
}

/**
 * Animation loop
 */
function animate() {
  requestAnimationFrame(animate);

  // Slow idle rotation when not rolling
  if (!isRolling && diceMesh) {
    diceMesh.rotation.x += 0.002;
    diceMesh.rotation.y += 0.003;
  }

  if (diceRenderer && diceScene && diceCamera) {
    diceRenderer.render(diceScene, diceCamera);
  }
}

/**
 * Resize renderer when container size changes
 */
function resizeDiceRenderer() {
  if (!diceContainer || !diceRenderer || !diceCamera) {
    return;
  }

  const width = diceContainer.clientWidth;
  const height = diceContainer.clientHeight;

  diceCamera.aspect = width / height;
  diceCamera.updateProjectionMatrix();

  diceRenderer.setSize(width, height);
}

/**
 * Clean up renderer resources
 */
function disposeDiceRenderer() {
  if (diceMesh) {
    diceScene.remove(diceMesh);
    diceMesh.geometry.dispose();
    diceMesh.material.forEach(mat => {
      if (mat.map) mat.map.dispose();
      mat.dispose();
    });
  }

  if (diceRenderer) {
    diceRenderer.dispose();
    if (diceContainer && diceRenderer.domElement) {
      diceContainer.removeChild(diceRenderer.domElement);
    }
  }

  diceScene = null;
  diceCamera = null;
  diceRenderer = null;
  diceMesh = null;
  diceContainer = null;
}

// Export to global scope
if (typeof window !== 'undefined') {
  window.DiceRenderer = {
    initDiceRenderer,
    createDice,
    rollDice,
    resizeDiceRenderer,
    disposeDiceRenderer
  };
}
