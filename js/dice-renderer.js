/**
 * 3D Dice Renderer
 * Renders and animates 3D dice using Three.js
 * Supports D20 and D6 (defense) with customizable face textures
 * Refactored to support multiple independent instances
 */

/**
 * DiceRenderer class - creates independent dice renderer instances
 */
class DiceRendererInstance {
  constructor() {
    this.scene = null;
    this.camera = null;
    this.renderer = null;
    this.mesh = null;
    this.container = null;
    this.isRolling = false;
    this.hasRolled = false;
    this.rollCallback = null;
    this.faceNormals = [];
    this.animationId = null;
    this.diceType = null; // 'd20' or 'd6-defense'
  }

  /**
   * Initialize the 3D dice renderer
   * @param {HTMLElement} container - DOM element to render into
   * @param {number} [bgColor=0x1a1410] - Three.js scene background color
   */
  init(container, bgColor = 0x1a1410) {
    this.container = container;

    // Create scene
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(bgColor);

    // Create camera
    const width = container.clientWidth;
    const height = container.clientHeight;
    this.camera = new THREE.PerspectiveCamera(50, width / height, 0.1, 1000);
    this.camera.position.z = 5;

    // Create renderer
    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setSize(width, height);
    container.appendChild(this.renderer.domElement);

    // Add lights
    const ambientLight = new THREE.AmbientLight(0xffffff, 0.6);
    this.scene.add(ambientLight);

    const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
    directionalLight.position.set(5, 5, 5);
    this.scene.add(directionalLight);

    // Start render loop
    this.animate();
  }

  /**
   * Create canvas texture for a D20 face with a number
   * @param {number} number - Number to display on face
   * @param {Object} side - Side data from dice system (optional)
   * @returns {THREE.CanvasTexture} Texture for the face
   */
  createD20FaceTexture(number, side = null) {
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
    const displayValue = side && side.displayValue !== null ? side.displayValue : (number || 1);
    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 48px Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    // Add text outline for better readability
    ctx.strokeStyle = '#000000';
    ctx.lineWidth = 6;
    ctx.strokeText(displayValue.toString(), 64, 81);
    ctx.fillText(displayValue.toString(), 64, 81);

    const texture = new THREE.CanvasTexture(canvas);
    texture.needsUpdate = true;
    return texture;
  }

  /**
   * Create canvas texture for a Defense D6 face with block value
   * @param {number} blockValue - Block value to display
   * @param {Object} side - Side data from dice system (optional)
   * @returns {THREE.CanvasTexture} Texture for the face
   */
  createDefenseFaceTexture(blockValue, side = null) {
    const canvas = document.createElement('canvas');
    canvas.width = 128;
    canvas.height = 128;
    const ctx = canvas.getContext('2d');

    // Background - blue/cyan theme
    ctx.fillStyle = '#66ccff';
    ctx.fillRect(0, 0, 128, 128);

    // Border
    ctx.strokeStyle = '#003366';
    ctx.lineWidth = 4;
    ctx.strokeRect(0, 0, 128, 128);

    // Display text: "X🛡️"
    const displayValue = side && side.displayValue !== null ? side.displayValue : blockValue;
    const displayText = side && side.displayText ? side.displayText : `${displayValue}🛡️`;

    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 40px Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    // Add text outline for better readability
    ctx.strokeStyle = '#000000';
    ctx.lineWidth = 6;
    ctx.strokeText(displayText, 64, 64);
    ctx.fillText(displayText, 64, 64);

    const texture = new THREE.CanvasTexture(canvas);
    texture.needsUpdate = true;
    return texture;
  }

  /**
   * Create canvas texture for an Enemy D6 face
   * @param {Object} side - Side data from dice system
   * @returns {THREE.CanvasTexture} Texture for the face
   */
  createEnemyFaceTexture(side) {
    const canvas = document.createElement('canvas');
    canvas.width = 128;
    canvas.height = 128;
    const ctx = canvas.getContext('2d');

    // Background - red theme for enemies
    ctx.fillStyle = '#cc3333';
    ctx.fillRect(0, 0, 128, 128);

    // Border
    ctx.strokeStyle = '#660000';
    ctx.lineWidth = 4;
    ctx.strokeRect(0, 0, 128, 128);

    // Display text from side
    const displayText = side.displayText || `${side.value}`;

    ctx.fillStyle = '#ffffff';
    ctx.font = 'bold 40px Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    // Add text outline for better readability
    ctx.strokeStyle = '#000000';
    ctx.lineWidth = 6;
    ctx.strokeText(displayText, 64, 64);
    ctx.fillText(displayText, 64, 64);

    const texture = new THREE.CanvasTexture(canvas);
    texture.needsUpdate = true;
    return texture;
  }

  /**
   * Create a D20 mesh with numbered faces
   * @param {Object} diceData - Dice data from dice system
   * @returns {THREE.Group} D20 as a group of face meshes
   */
  createD20Mesh(diceData) {
    // Create base icosahedron geometry - larger for better visibility
    // Use subdivision level 1 for smoother, more rounded appearance
    const baseGeometry = new THREE.IcosahedronGeometry(1.6, 1);

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
    this.faceNormals = [];

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
      this.faceNormals.push(faceNormal);

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
      // With subdivision, we have more faces than numbers, so cycle through them
      const number = faceNumberMap[faceIndex % faceNumberMap.length] || (faceIndex % 20) + 1;
      const sideIndex = number - 1;
      const side = diceData.sides[sideIndex] || { value: number, displayValue: null };
      const texture = this.createD20FaceTexture(number, side);

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
   * Create a D6 mesh with block value faces
   * @param {Object} diceData - Dice data from dice system (d6-defense or enemy dice)
   * @returns {THREE.Mesh} D6 cube mesh
   */
  createD6Mesh(diceData) {
    // Create cube geometry - larger for better readability
    // Use segments for smoother edges (closer to rounded appearance)
    const geometry = new THREE.BoxGeometry(2.0, 2.0, 2.0, 4, 4, 4);

    const materials = [];

    // Cube face normals in order: right, left, top, bottom, front, back
    const cubeNormals = [
      new THREE.Vector3(1, 0, 0),
      new THREE.Vector3(-1, 0, 0),
      new THREE.Vector3(0, 1, 0),
      new THREE.Vector3(0, -1, 0),
      new THREE.Vector3(0, 0, 1),
      new THREE.Vector3(0, 0, -1)
    ];

    this.faceNormals = [];

    // Check if this is an enemy dice
    const isEnemyDice = diceData.type.startsWith('d6-enemy');

    for (let i = 0; i < 6; i++) {
      const side = diceData.sides[i];

      // Use appropriate texture based on dice type
      let texture;
      if (isEnemyDice) {
        texture = this.createEnemyFaceTexture(side);
      } else {
        const blockValue = side.value;
        texture = this.createDefenseFaceTexture(blockValue, side);
      }

      const material = new THREE.MeshStandardMaterial({
        map: texture,
        roughness: 0.5,
        metalness: 0.1
      });

      materials.push(material);
      this.faceNormals.push(cubeNormals[i].clone());
    }

    const mesh = new THREE.Mesh(geometry, materials);
    console.log('D6 created with', materials.length, 'faces');
    return mesh;
  }

  /**
   * Create and add a dice to the scene
   * @param {Object} diceData - Dice data from dice system
   */
  createDice(diceData) {
    // Remove old dice if it exists
    if (this.mesh) {
      this.scene.remove(this.mesh);

      // Dispose of old mesh
      if (this.mesh.children) {
        // Group of meshes (D20)
        this.mesh.children.forEach(faceMesh => {
          if (faceMesh.geometry) faceMesh.geometry.dispose();
          if (faceMesh.material) {
            if (faceMesh.material.map) faceMesh.material.map.dispose();
            faceMesh.material.dispose();
          }
        });
      } else {
        // Single mesh (D6)
        if (this.mesh.geometry) this.mesh.geometry.dispose();
        if (this.mesh.material) {
          if (Array.isArray(this.mesh.material)) {
            this.mesh.material.forEach(mat => {
              if (mat.map) mat.map.dispose();
              mat.dispose();
            });
          } else {
            if (this.mesh.material.map) this.mesh.material.map.dispose();
            this.mesh.material.dispose();
          }
        }
      }
    }

    // Reset roll state for new dice
    this.hasRolled = false;
    this.diceType = diceData.type;

    // Create new dice based on type
    if (diceData.type === 'd6-defense' || diceData.type.startsWith('d6-enemy')) {
      this.mesh = this.createD6Mesh(diceData);
    } else {
      // Default to D20
      this.mesh = this.createD20Mesh(diceData);
    }

    this.scene.add(this.mesh);
  }

  /**
   * Roll the dice with animation
   * @param {Object} diceData - Dice data from dice system
   * @param {number} result - Pre-determined result from dice system
   * @param {Function} callback - Callback when roll completes
   */
  rollDice(diceData, result, callback) {
    if (this.isRolling) {
      console.warn('Dice is already rolling');
      return;
    }

    this.isRolling = true;
    this.hasRolled = true;
    this.rollCallback = callback;

    // Animation duration (1.5 seconds)
    const duration = 1500;
    const startTime = Date.now();

    // Store starting rotation as quaternion
    const startQuat = new THREE.Quaternion().setFromEuler(this.mesh.rotation);

    // Calculate target rotation to show the rolled face
    const targetRotation = this.calculateFaceRotation(result);
    const targetEuler = new THREE.Euler(targetRotation.x, targetRotation.y, targetRotation.z, 'XYZ');
    const targetQuat = new THREE.Quaternion().setFromEuler(targetEuler);

    // Add some extra spins for visual effect (2-3 full rotations)
    const extraSpins = 2 + Math.random();
    const spinAxis = new THREE.Vector3(
      Math.random() - 0.5,
      Math.random() - 0.5,
      Math.random() - 0.5
    ).normalize();

    const animateRoll = () => {
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
        this.mesh.rotation.setFromQuaternion(currentQuat);

        requestAnimationFrame(animateRoll);
      } else {
        // Final position - ensure exact target rotation
        this.mesh.rotation.set(targetRotation.x, targetRotation.y, targetRotation.z);

        this.isRolling = false;

        if (this.rollCallback) {
          this.rollCallback(result);
          this.rollCallback = null;
        }
      }
    };

    // Start roll animation with a jump
    this.animateDiceJump(() => {
      animateRoll();
    });
  }

  /**
   * Animate dice jumping up before rolling
   * @param {Function} callback - Callback when jump completes
   */
  animateDiceJump(callback) {
    const jumpHeight = 1.5;
    const jumpDuration = 300;
    const startY = this.mesh.position.y;
    const startTime = Date.now();

    const jump = () => {
      const elapsed = Date.now() - startTime;
      const progress = Math.min(elapsed / jumpDuration, 1);

      if (progress < 0.5) {
        // Jump up
        this.mesh.position.y = startY + (jumpHeight * (progress * 2));
      } else {
        // Fall down
        this.mesh.position.y = startY + (jumpHeight * (1 - (progress - 0.5) * 2));
      }

      if (progress < 1) {
        requestAnimationFrame(jump);
      } else {
        this.mesh.position.y = startY;
        callback();
      }
    };

    jump();
  }

  /**
   * Calculate rotation to orient a specific face toward the camera
   * @param {number} faceNumber - The face number to show
   * @returns {Object} Rotation object {x, y, z}
   */
  calculateFaceRotation(faceNumber) {
    // For D6 (defense or enemy), faceNumber is 1-6 and maps directly to face index 0-5
    // For D20, use the face number map
    let faceIndex;

    if (this.diceType === 'd6-defense' || this.diceType.startsWith('d6-enemy')) {
      faceIndex = faceNumber - 1;
    } else {
      // D20 face numbering mapping
      const faceNumberMap = [
        1, 20, 2, 19, 3, 18, 4, 17, 5, 16,
        6, 15, 7, 14, 8, 13, 9, 12, 10, 11
      ];
      faceIndex = faceNumberMap.indexOf(faceNumber);
    }

    if (faceIndex === -1 || !this.faceNormals[faceIndex]) {
      console.warn('Invalid face number or missing normal:', faceNumber);
      return { x: 0, y: 0, z: 0 };
    }

    // Get the face normal
    const normal = this.faceNormals[faceIndex];

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
  animate() {
    this.animationId = requestAnimationFrame(() => this.animate());

    // Slow idle rotation when not rolling and hasn't been rolled yet
    if (!this.isRolling && !this.hasRolled && this.mesh) {
      this.mesh.rotation.x += 0.002;
      this.mesh.rotation.y += 0.003;
    }

    if (this.renderer && this.scene && this.camera) {
      this.renderer.render(this.scene, this.camera);
    }
  }

  /**
   * Resize renderer when container size changes
   */
  resize() {
    if (!this.container || !this.renderer || !this.camera) {
      return;
    }

    const width = this.container.clientWidth;
    const height = this.container.clientHeight;

    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();

    this.renderer.setSize(width, height);
  }

  /**
   * Clean up renderer resources
   */
  dispose() {
    // Stop animation loop
    if (this.animationId) {
      cancelAnimationFrame(this.animationId);
      this.animationId = null;
    }

    if (this.mesh) {
      this.scene.remove(this.mesh);

      // Dispose of mesh resources
      if (this.mesh.children) {
        // Group of meshes (D20)
        this.mesh.children.forEach(faceMesh => {
          if (faceMesh.geometry) faceMesh.geometry.dispose();
          if (faceMesh.material) {
            if (faceMesh.material.map) faceMesh.material.map.dispose();
            faceMesh.material.dispose();
          }
        });
      } else {
        // Single mesh (D6)
        if (this.mesh.geometry) this.mesh.geometry.dispose();
        if (this.mesh.material) {
          if (Array.isArray(this.mesh.material)) {
            this.mesh.material.forEach(mat => {
              if (mat.map) mat.map.dispose();
              mat.dispose();
            });
          } else {
            if (this.mesh.material.map) this.mesh.material.map.dispose();
            this.mesh.material.dispose();
          }
        }
      }
    }

    if (this.renderer) {
      this.renderer.dispose();
      if (this.container && this.renderer.domElement) {
        this.container.removeChild(this.renderer.domElement);
      }
    }

    this.scene = null;
    this.camera = null;
    this.renderer = null;
    this.mesh = null;
    this.container = null;
    this.isRolling = false;
    this.hasRolled = false;
    this.rollCallback = null;
    this.faceNormals = [];
  }
}

// Export to global scope
if (typeof window !== 'undefined') {
  window.DiceRendererInstance = DiceRendererInstance;
}
