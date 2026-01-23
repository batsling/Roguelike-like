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
let hasRolled = false;
let rollCallback = null;
let faceNormals = []; // Store face normals for rotation calculations

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

  // Number - sized and positioned for triangular face
  const displayValue = side && side.displayValue !== null ? side.displayValue : number;
  ctx.fillStyle = '#ffffff';
  ctx.font = 'bold 48px Arial';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  // Triangle UVs: (0.1,0.1), (0.9,0.1), (0.5,0.9)
  // In canvas coords (Y flipped): (12.8,115.2), (115.2,115.2), (64,12.8)
  // Centroid: (64, 81)
  ctx.fillText(displayValue.toString(), 64, 81);

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

  // Reset face normals array
  faceNormals = [];

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

    // Calculate face normal (outward pointing)
    const edge1 = new THREE.Vector3().subVectors(v1, v0);
    const edge2 = new THREE.Vector3().subVectors(v2, v0);
    const faceNormal = new THREE.Vector3().crossVectors(edge1, edge2).normalize();
    faceNormals.push(faceNormal);

    // Create triangle geometry for this face
    const faceGeometry = new THREE.BufferGeometry();
    const faceVertices = new Float32Array([
      v0.x, v0.y, v0.z,
      v1.x, v1.y, v1.z,
      v2.x, v2.y, v2.z
    ]);
    faceGeometry.setAttribute('position', new THREE.BufferAttribute(faceVertices, 3));

    // Create UVs for texture mapping - map to center portion of texture
    // This helps center the number on the triangular face
    const uvs = new Float32Array([
      0.1, 0.1,   // Bottom left
      0.9, 0.1,   // Bottom right
      0.5, 0.9    // Top center
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

  // Reset roll state for new dice
  hasRolled = false;

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
  hasRolled = true;
  rollCallback = callback;

  // Animation duration (1.5 seconds)
  const duration = 1500;
  const startTime = Date.now();

  // Store starting rotation as quaternion
  const startQuat = new THREE.Quaternion().setFromEuler(diceMesh.rotation);

  // Calculate target rotation to show the rolled face
  const targetRotation = calculateFaceRotation(result);
  const targetEuler = new THREE.Euler(targetRotation.x, targetRotation.y, targetRotation.z, 'XYZ');
  const targetQuat = new THREE.Quaternion().setFromEuler(targetEuler);

  // Add some extra spins for visual effect (2-3 full rotations)
  const extraSpins = 2 + Math.random();
  const spinAxis = new THREE.Vector3(
    Math.random() - 0.5,
    Math.random() - 0.5,
    Math.random() - 0.5
  ).normalize();

  function animateRoll() {
    const elapsed = Date.now() - startTime;
    const progress = Math.min(elapsed / duration, 1);

    if (progress < 1) {
      // Ease out curve for smooth deceleration
      const easeProgress = 1 - Math.pow(1 - progress, 3);

      // Create intermediate quaternion
      const currentQuat = new THREE.Quaternion();

      // First 70% of animation: mostly spinning
      // Last 30%: smoothly rotate to final position
      if (progress < 0.7) {
        // Spinning phase with extra rotations
        const spinAmount = extraSpins * Math.PI * 2 * progress / 0.7;
        const spinQuat = new THREE.Quaternion().setFromAxisAngle(spinAxis, spinAmount);
        currentQuat.multiplyQuaternions(spinQuat, startQuat);
      } else {
        // Transition phase - blend from spinning to target
        const blendProgress = (progress - 0.7) / 0.3; // 0 to 1 over last 30%
        const blendEase = 1 - Math.pow(1 - blendProgress, 2); // Ease into final position

        // Calculate final spin position
        const spinAmount = extraSpins * Math.PI * 2;
        const spinQuat = new THREE.Quaternion().setFromAxisAngle(spinAxis, spinAmount);
        const finalSpinQuat = new THREE.Quaternion().multiplyQuaternions(spinQuat, startQuat);

        // Smoothly interpolate from spin to target
        currentQuat.slerpQuaternions(finalSpinQuat, targetQuat, blendEase);
      }

      // Apply the rotation
      diceMesh.rotation.setFromQuaternion(currentQuat);

      requestAnimationFrame(animateRoll);
    } else {
      // Final position - ensure exact target rotation
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
 * Calculate rotation to orient a specific face toward the camera
 * @param {number} faceNumber - The face number to show (1-20)
 * @returns {Object} Rotation object {x, y, z}
 */
function calculateFaceRotation(faceNumber) {
  // Face number to face index (0-based)
  const faceNumberMap = [
    1, 20, 2, 19, 3, 18, 4, 17, 5, 16,
    6, 15, 7, 14, 8, 13, 9, 12, 10, 11
  ];
  const faceIndex = faceNumberMap.indexOf(faceNumber);

  if (faceIndex === -1 || !faceNormals[faceIndex]) {
    console.warn('Invalid face number or missing normal:', faceNumber);
    return { x: 0, y: 0, z: 0 };
  }

  // Get the face normal
  const normal = faceNormals[faceIndex];

  // We want the face normal to point toward the camera (which is at z=5 looking at origin)
  // Camera looks down negative Z, so we want normal to point at +Z
  const targetDirection = new THREE.Vector3(0, 0, 1);

  // Calculate rotation needed to align normal with target
  const quaternion = new THREE.Quaternion();
  quaternion.setFromUnitVectors(normal, targetDirection);

  // Convert quaternion to Euler angles
  const euler = new THREE.Euler();
  euler.setFromQuaternion(quaternion, 'XYZ');

  console.log(`Face ${faceNumber} rotation:`, euler.x, euler.y, euler.z);

  return { x: euler.x, y: euler.y, z: euler.z };
}

/**
 * Animation loop
 */
function animate() {
  requestAnimationFrame(animate);

  // Slow idle rotation when not rolling and hasn't been rolled yet
  if (!isRolling && !hasRolled && diceMesh) {
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

    // Dispose of all face meshes in the group
    diceMesh.children.forEach(faceMesh => {
      if (faceMesh.geometry) faceMesh.geometry.dispose();
      if (faceMesh.material) {
        if (faceMesh.material.map) faceMesh.material.map.dispose();
        faceMesh.material.dispose();
      }
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
  isRolling = false;
  hasRolled = false;
  rollCallback = null;
  faceNormals = [];
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
