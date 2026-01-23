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
 * @returns {THREE.Group} D20 as a group of face meshes
 */
function createD20Mesh(diceData) {
  // Create base icosahedron geometry
  const baseGeometry = new THREE.IcosahedronGeometry(1, 0);

  // Convert to non-indexed geometry if needed
  const geometry = baseGeometry.index ? baseGeometry.toNonIndexed() : baseGeometry;
  const positions = geometry.attributes.position.array;

  // D20 face numbering mapping
  const faceNumberMap = [
    1, 20, 2, 19, 3, 18, 4, 17, 5, 16,
    6, 15, 7, 14, 8, 13, 9, 12, 10, 11
  ];

  // Create a group to hold all face meshes
  const d20Group = new THREE.Group();

  // Icosahedron has 20 faces, each face is a triangle (3 vertices)
  // Non-indexed geometry has 60 vertices (20 faces * 3 vertices each)
  const numFaces = positions.length / 9; // 9 floats per triangle (3 vertices * 3 components)

  console.log('Creating D20 with', numFaces, 'faces from', positions.length, 'position values');

  // Create each face as a separate triangle mesh
  for (let faceIndex = 0; faceIndex < numFaces; faceIndex++) {
    // Each face has 3 vertices, each vertex has 3 components (x, y, z)
    const vertexStart = faceIndex * 9;

    // Get vertex positions directly from non-indexed geometry
    const v0 = new THREE.Vector3(
      positions[vertexStart + 0],
      positions[vertexStart + 1],
      positions[vertexStart + 2]
    );
    const v1 = new THREE.Vector3(
      positions[vertexStart + 3],
      positions[vertexStart + 4],
      positions[vertexStart + 5]
    );
    const v2 = new THREE.Vector3(
      positions[vertexStart + 6],
      positions[vertexStart + 7],
      positions[vertexStart + 8]
    );

    // Create triangle geometry for this face
    const faceGeometry = new THREE.BufferGeometry();
    const faceVertices = new Float32Array([
      v0.x, v0.y, v0.z,
      v1.x, v1.y, v1.z,
      v2.x, v2.y, v2.z
    ]);
    faceGeometry.setAttribute('position', new THREE.BufferAttribute(faceVertices, 3));

    // Create UVs for texture mapping
    const uvs = new Float32Array([
      0, 0,
      1, 0,
      0.5, 1
    ]);
    faceGeometry.setAttribute('uv', new THREE.BufferAttribute(uvs, 2));

    // Compute normals
    faceGeometry.computeVertexNormals();

    // Get the number for this face
    const number = faceNumberMap[faceIndex];
    const sideIndex = number - 1;
    const side = diceData.sides[sideIndex];
    const texture = createFaceTexture(number, side);

    // Create material with texture
    const material = new THREE.MeshStandardMaterial({
      map: texture,
      roughness: 0.5,
      metalness: 0.1,
      side: THREE.DoubleSide
    });

    // Create mesh and add to group
    const faceMesh = new THREE.Mesh(faceGeometry, material);
    d20Group.add(faceMesh);
  }

  console.log('D20 created with', d20Group.children.length, 'face meshes');

  return d20Group;
}

/**
 * Create and add a dice to the scene
 * @param {Object} diceData - Dice data from dice system
 */
function createDice(diceData) {
  // Remove old dice if it exists
  if (diceMesh) {
    diceScene.remove(diceMesh);

    // Dispose of all face meshes in the group
    diceMesh.children.forEach(faceMesh => {
      if (faceMesh.geometry) faceMesh.geometry.dispose();
      if (faceMesh.material) {
        if (faceMesh.material.map) faceMesh.material.map.dispose();
        faceMesh.material.dispose();
      }
    });
  }

  // Create new dice (now a Group of face meshes)
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
