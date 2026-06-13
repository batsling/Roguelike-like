/**
 * 3D Dice Renderer
 * Renders and animates 3D dice using Three.js
 * Supports proper-shape D4 (tetrahedron), D6 (cube), D8 (octahedron),
 * D10 (pentagonal trapezohedron), D12 (dodecahedron), and D20 (icosahedron),
 * each with per-face number textures using the real-die "opposites sum to
 * N+1" numbering convention (where opposite faces exist).
 *
 * Refactored to support multiple independent instances.
 */

/**
 * Per-shape face data for d4/d8/d10/d12. Returns:
 *   {
 *     faces: [{
 *       vertices: Array<THREE.Vector3>,  // 3+ vertices going around the face
 *       centroid: THREE.Vector3,
 *       normal:   THREE.Vector3,         // outward, unit length
 *     }]
 *   }
 * Vertex order is CCW when viewed from outside (front-facing normal).
 *
 * `radius` is the circumradius (distance from center to any vertex).
 * Face numbering (faceValues) is computed AFTER face data using the
 * opposite-sum-to-(N+1) convention for shapes with parallel opposite faces.
 */
function _buildPolyhedronFaceData(sides, radius) {
  const F = []; // accumulated faces
  const phi = (1 + Math.sqrt(5)) / 2;

  if (sides === 4) {
    // Regular tetrahedron with vertices at alternating cube corners
    // Edge length ~ 2*sqrt(2); scaled to fit circumradius
    const r = radius / Math.sqrt(3);
    const V = [
      new THREE.Vector3( r,  r,  r),
      new THREE.Vector3( r, -r, -r),
      new THREE.Vector3(-r,  r, -r),
      new THREE.Vector3(-r, -r,  r),
    ];
    // Each face opposes one vertex; vertex winding is CCW from outside.
    const triplets = [
      [1, 3, 2], // opposite V0
      [0, 2, 3], // opposite V1
      [0, 3, 1], // opposite V2
      [0, 1, 2], // opposite V3
    ];
    for (const [a, b, c] of triplets) {
      F.push({ vertices: [V[a], V[b], V[c]] });
    }
  } else if (sides === 6) {
    // Cube: 6 square faces. Circumradius = side*sqrt(3)/2; pick side so r = radius.
    const s = radius / Math.sqrt(3);
    // CCW vertex order viewed from outside the face
    const faces = [
      // +X face
      [[s, -s, -s], [s,  s, -s], [s,  s,  s], [s, -s,  s]],
      // -X face
      [[-s, -s,  s], [-s,  s,  s], [-s,  s, -s], [-s, -s, -s]],
      // +Y face
      [[-s,  s,  s], [ s,  s,  s], [ s,  s, -s], [-s,  s, -s]],
      // -Y face
      [[-s, -s, -s], [ s, -s, -s], [ s, -s,  s], [-s, -s,  s]],
      // +Z face
      [[-s, -s,  s], [ s, -s,  s], [ s,  s,  s], [-s,  s,  s]],
      // -Z face
      [[ s, -s, -s], [-s, -s, -s], [-s,  s, -s], [ s,  s, -s]],
    ];
    for (const verts of faces) {
      F.push({ vertices: verts.map(v => new THREE.Vector3(v[0], v[1], v[2])) });
    }
  } else if (sides === 8) {
    // Regular octahedron: 6 vertices at ±axes, 8 triangular faces
    const r = radius;
    const V = [
      new THREE.Vector3( r,  0,  0), // 0 +X
      new THREE.Vector3(-r,  0,  0), // 1 -X
      new THREE.Vector3( 0,  r,  0), // 2 +Y
      new THREE.Vector3( 0, -r,  0), // 3 -Y
      new THREE.Vector3( 0,  0,  r), // 4 +Z
      new THREE.Vector3( 0,  0, -r), // 5 -Z
    ];
    // 8 faces, one per octant, with CCW winding viewed from outside
    const triplets = [
      [0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4], // +Z hemisphere
      [2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5], // -Z hemisphere
    ];
    for (const [a, b, c] of triplets) {
      F.push({ vertices: [V[a], V[b], V[c]] });
    }
  } else if (sides === 10) {
    // Pentagonal trapezohedron: 2 apices + 10 equator vertices in two
    // staggered pentagons. 10 kite faces. Real d10 shape.
    const apexH = radius * 0.95;    // apex distance from center
    const eqR   = radius * 0.78;    // equator ring radius
    const eqH   = radius * 0.28;    // equator vertical offset
    const N = new THREE.Vector3(0,  apexH, 0);
    const S = new THREE.Vector3(0, -apexH, 0);
    // 10 equator vertices, even-index = "up", odd-index = "down"
    const eq = [];
    for (let i = 0; i < 10; i++) {
      const angle = i * (Math.PI / 5);     // 36° apart
      const y = (i % 2 === 0) ? +eqH : -eqH;
      eq.push(new THREE.Vector3(eqR * Math.cos(angle), y, eqR * Math.sin(angle)));
    }
    // 5 top kites (N apex). Each kite: [N, up_i, down_i, up_{i+1}] CCW from outside
    for (let i = 0; i < 5; i++) {
      const up_i   = eq[(2 * i) % 10];
      const down_i = eq[(2 * i + 1) % 10];
      const up_n   = eq[(2 * i + 2) % 10];
      F.push({ vertices: [N, up_n, down_i, up_i] });
    }
    // 5 bottom kites (S apex). Each kite: [S, down_i, up_{i+1}, down_{i+1}] CCW from outside
    for (let i = 0; i < 5; i++) {
      const down_i = eq[(2 * i + 1) % 10];
      const up_n   = eq[(2 * i + 2) % 10];
      const down_n = eq[(2 * i + 3) % 10];
      F.push({ vertices: [S, down_n, up_n, down_i] });
    }
  } else if (sides === 12) {
    // Regular dodecahedron: 20 vertices, 12 pentagonal faces.
    // Vertices at (±1,±1,±1) and cyclic permutations of (0, ±1/φ, ±φ).
    const a = radius / Math.sqrt(3);   // scale so circumradius = radius
    const b = a / phi;
    const c = a * phi;
    const V = [
      new THREE.Vector3( a,  a,  a), new THREE.Vector3( a,  a, -a),
      new THREE.Vector3( a, -a,  a), new THREE.Vector3( a, -a, -a),
      new THREE.Vector3(-a,  a,  a), new THREE.Vector3(-a,  a, -a),
      new THREE.Vector3(-a, -a,  a), new THREE.Vector3(-a, -a, -a),
      new THREE.Vector3( 0,  b,  c), new THREE.Vector3( 0,  b, -c),
      new THREE.Vector3( 0, -b,  c), new THREE.Vector3( 0, -b, -c),
      new THREE.Vector3( b,  c,  0), new THREE.Vector3( b, -c,  0),
      new THREE.Vector3(-b,  c,  0), new THREE.Vector3(-b, -c,  0),
      new THREE.Vector3( c,  0,  b), new THREE.Vector3( c,  0, -b),
      new THREE.Vector3(-c,  0,  b), new THREE.Vector3(-c,  0, -b),
    ];
    // 12 pentagonal faces, vertex indices CCW from outside.
    const facesIdx = [
      [ 0,  8, 10,  2, 16],  // +X+Y front
      [ 0, 16, 17,  1, 12],  // +X+Y top
      [12, 14,  4,  8,  0],  // +Y front (alt: visible)
      [16,  2, 13,  3, 17],  // +X front-right
      [ 9,  1, 17,  3, 11],  // +X back
      [ 1,  9,  5, 14, 12],  // top back
      [ 8,  4, 18,  6, 10],  // +Z left
      [ 2, 10,  6, 15, 13],  // -Y front
      [14,  5, 19, 18,  4],  // -X top
      [ 5,  9, 11,  7, 19],  // back left
      [ 3, 13, 15,  7, 11],  // -Y back
      [ 6, 18, 19,  7, 15],  // -X back
    ];
    for (const ring of facesIdx) {
      F.push({ vertices: ring.map(i => V[i]) });
    }
  } else {
    throw new Error(`Unsupported polyhedron side count: ${sides}`);
  }

  // Compute centroid & outward normal for each face. Flip normal if it
  // points inward (shouldn't happen with correct winding above, but be safe).
  for (const face of F) {
    const verts = face.vertices;
    const centroid = new THREE.Vector3();
    verts.forEach(v => centroid.add(v));
    centroid.multiplyScalar(1 / verts.length);

    // Normal from first 3 vertices (CCW winding → outward)
    const e1 = new THREE.Vector3().subVectors(verts[1], verts[0]);
    const e2 = new THREE.Vector3().subVectors(verts[2], verts[0]);
    const normal = new THREE.Vector3().crossVectors(e1, e2).normalize();
    // Sanity-check: outward normal should have positive dot with centroid
    if (normal.dot(centroid) < 0) normal.negate();

    face.centroid = centroid;
    face.normal = normal;
  }

  return { faces: F };
}

/**
 * Assign face values 1..N using the real-die "opposite faces sum to N+1"
 * convention. For shapes without parallel opposite faces (tetrahedron),
 * faces get sequential values 1..N.
 *
 * Returns an array `faceValues[i] = value` aligned to `faceData.faces[i]`.
 */
function _assignFaceValues(faceData, sides) {
  const N = faceData.faces.length;
  const values = new Array(N).fill(null);

  if (sides === 4) {
    // Tetrahedron: no opposite faces. Sequential.
    for (let i = 0; i < N; i++) values[i] = i + 1;
    return values;
  }

  // Build opposite-face map by anti-parallel normal lookup
  const oppositeOf = new Array(N).fill(-1);
  for (let i = 0; i < N; i++) {
    if (oppositeOf[i] !== -1) continue;
    for (let j = i + 1; j < N; j++) {
      if (oppositeOf[j] !== -1) continue;
      const dot = faceData.faces[i].normal.dot(faceData.faces[j].normal);
      if (dot < -0.99) {  // anti-parallel within ~8° tolerance
        oppositeOf[i] = j;
        oppositeOf[j] = i;
        break;
      }
    }
  }

  // Walk faces in order, assigning pairs (k, N+1-k).
  let next = 1;
  for (let i = 0; i < N; i++) {
    if (values[i] !== null) continue;
    const opp = oppositeOf[i];
    if (opp === -1) {
      // No detected opposite — fall back to sequential
      values[i] = next++;
    } else {
      values[i] = next;
      values[opp] = N + 1 - next;
      next++;
    }
  }
  return values;
}



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
    this.renderer.domElement.style.pointerEvents = 'none';
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
    const baseGeometry = new THREE.IcosahedronGeometry(1.6, 0);

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


    return d20Group;
  }

  /**
   * Create canvas texture for a card-dice face.
   * Colors come from diceData.colors (set per die name in _makeDiceDataForCard).
   */
  createCardDiceFaceTexture(side, colors) {
    const c = colors || { bg: '#7a4800', inner: '#a86000', border: '#f0b030', faceNum: '#ffd060', text: '#ffe8a0', outline: '#3a2000' };
    const canvas = document.createElement('canvas');
    canvas.width = 128;
    canvas.height = 128;
    const ctx = canvas.getContext('2d');

    ctx.fillStyle = c.bg;
    ctx.fillRect(0, 0, 128, 128);
    ctx.fillStyle = c.inner;
    ctx.fillRect(4, 4, 120, 120);
    ctx.strokeStyle = c.border;
    ctx.lineWidth = 4;
    ctx.strokeRect(2, 2, 124, 124);

    // Face number (top-left, small)
    ctx.fillStyle = c.faceNum;
    ctx.font = 'bold 18px Arial';
    ctx.textAlign = 'left';
    ctx.textBaseline = 'top';
    ctx.fillText(String(side.face), 8, 6);

    // Label text (centered, wrapped)
    const label = side.text || String(side.face);
    ctx.fillStyle = c.text;
    ctx.font = 'bold 16px Arial';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.strokeStyle = c.outline;
    ctx.lineWidth = 3;

    // Word-wrap the label into max 2 lines
    const words = label.split(' ');
    const lines = [];
    let cur = '';
    for (const w of words) {
      const test = cur ? cur + ' ' + w : w;
      if (ctx.measureText(test).width > 108 && cur) { lines.push(cur); cur = w; }
      else cur = test;
    }
    if (cur) lines.push(cur);
    const lineH = 20;
    const startY = 64 - ((lines.length - 1) * lineH) / 2;
    lines.forEach((line, li) => {
      ctx.strokeText(line, 64, startY + li * lineH);
      ctx.fillText(line, 64, startY + li * lineH);
    });

    const texture = new THREE.CanvasTexture(canvas);
    texture.needsUpdate = true;
    return texture;
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
    const isCardDice  = diceData.type === 'd6-card';

    for (let i = 0; i < 6; i++) {
      const side = diceData.sides[i];

      // Use appropriate texture based on dice type
      let texture;
      if (isCardDice) {
        texture = this.createCardDiceFaceTexture(side, diceData.colors);
      } else if (isEnemyDice) {
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
    return mesh;
  }

  /**
   * Create canvas texture for a numbered polyhedral face.
   *
   * `number` is the geometric face's conventional value (e.g. for a d6,
   * the face positioned at geometric slot N gets value N by the
   * opposites-sum-to-7 numbering). `side` (optional) is the
   * dice-system per-side data — if it has `displayValue`, that's painted
   * instead of `number`, allowing items to visibly alter individual faces.
   *
   * Font size scales by face shape: triangular faces (d4, d8) and kite
   * faces (d10) have less usable area than squares (d6) or pentagons (d12),
   * so the printed digit shrinks to stay inside the visible polygon.
   */
  createPolyhedralFaceTexture(number, sides, theme, side = null) {
    const c = theme || {
      bg: '#cc3333', border: '#660000', text: '#ffffff', outline: '#000000',
    };
    const canvas = document.createElement('canvas');
    canvas.width  = 128;
    canvas.height = 128;
    const ctx = canvas.getContext('2d');

    ctx.fillStyle = c.bg;
    ctx.fillRect(0, 0, 128, 128);
    ctx.strokeStyle = c.border;
    ctx.lineWidth = 4;
    ctx.strokeRect(0, 0, 128, 128);

    // Per-side displayValue overrides the conventional number so a modified
    // face shows the new value (e.g. an item that turns face 1 into a 20).
    const displayed = (side && side.displayValue !== null && side.displayValue !== undefined)
      ? side.displayValue : number;
    const text = String(displayed);

    // Font size by polyhedron — triangular faces (d4/d8) have ~50% of the
    // canvas's usable area, kites (d10) are tall+narrow, pentagons (d12)
    // are roomier than triangles but smaller than squares.
    let fontPx;
    let yOffset = 0;
    switch (sides) {
      case 4:  fontPx = 44; yOffset = 10; break;  // triangle face, nudge down so digit sits in the wider lower half
      case 6:  fontPx = 56; break;                // square face
      case 8:  fontPx = 44; yOffset = 10; break;  // triangle face
      case 10: fontPx = 44; yOffset = 8;  break;  // kite face, slight nudge to centroid
      case 12: fontPx = 50; break;                // pentagonal face
      default: fontPx = 48;
    }
    // Long strings (item-set displayValue like "100" or "X") need shrinking
    if (text.length >= 3) fontPx = Math.round(fontPx * 0.72);
    else if (text.length === 2) fontPx = Math.round(fontPx * 0.88);

    ctx.font = `bold ${fontPx}px Arial`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.strokeStyle = c.outline;
    ctx.lineWidth = Math.max(3, Math.round(fontPx * 0.1));
    ctx.strokeText(text, 64, 64 + yOffset);
    ctx.fillStyle = c.text;
    ctx.fillText(text, 64, 64 + yOffset);

    // Underline 6/9 (and 8 on d10) so flipped orientation is unambiguous
    const numericDisplayed = Number(displayed);
    const needsUnderline = (numericDisplayed === 6 || numericDisplayed === 9 || (sides === 10 && numericDisplayed === 8));
    if (needsUnderline) {
      ctx.fillStyle = c.text;
      const underlineY = 64 + yOffset + Math.round(fontPx * 0.5) + 4;
      const underlineW = Math.round(fontPx * 0.5);
      ctx.fillRect(64 - underlineW / 2, underlineY, underlineW, 3);
    }

    const tex = new THREE.CanvasTexture(canvas);
    tex.needsUpdate = true;
    return tex;
  }

  /**
   * Build a Group containing one textured polygon mesh per face of the
   * requested polyhedron. Real-die shapes are used (tetrahedron / cube /
   * octahedron / pentagonal trapezohedron / dodecahedron). Face values
   * follow the "opposite faces sum to N+1" convention where applicable.
   *
   * Requires diceData.shape === 'polyhedral' and diceData.sides in {4,6,8,10,12}.
   * Optional: diceData.colors (theme: { bg, border, text, outline, sceneBg }),
   *           diceData.radius (default 1.6 to match d20 scale).
   */
  createPolyhedralMesh(diceData) {
    const sides = diceData.sides;
    const radius = diceData.radius || 1.6;
    const theme = diceData.colors || {
      bg: '#cc3333', border: '#660000', text: '#ffffff', outline: '#000000',
    };

    const faceData = _buildPolyhedronFaceData(sides, radius);
    const faceValues = _assignFaceValues(faceData, sides);

    // Store normals indexed by face index so faceValueToIndex can recover
    // the face for any given value (used by calculateFaceRotation).
    this.faceNormals = faceData.faces.map(f => f.normal.clone());
    this.diceFaceValues = faceValues.slice();

    const group = new THREE.Group();

    // Per-face overrides come from diceData.sidesArray (an array of side
    // objects from dice-system). The polyhedral path uses diceData.sides as
    // the *count*, so we read the array from sidesArray instead. Items
    // setting displayValue on a side here visibly relabel that face.
    const overrides = Array.isArray(diceData.sidesArray) ? diceData.sidesArray : null;

    faceData.faces.forEach((face, idx) => {
      const value = faceValues[idx];
      const side = overrides ? (overrides[value - 1] || null) : null;
      const texture = this.createPolyhedralFaceTexture(value, sides, theme, side);

      // Build a triangle fan from the face vertices (works for triangles,
      // quads, kites, and pentagons alike). UVs map the number texture
      // across the face with a small inset so the digit sits near the center.
      const verts = face.vertices;
      const positions = [];
      const uvs = [];

      // Compute UV basis in face plane (right & up) around the centroid
      // so we can project each vertex into 2D UV coordinates centered on
      // the face. Then normalize to [inset, 1-inset].
      const right = new THREE.Vector3().subVectors(verts[0], face.centroid).normalize();
      const up = new THREE.Vector3().crossVectors(face.normal, right).normalize();
      const proj = verts.map(v => {
        const d = new THREE.Vector3().subVectors(v, face.centroid);
        return { u: d.dot(right), v: d.dot(up) };
      });
      const maxAbs = proj.reduce((m, p) => Math.max(m, Math.abs(p.u), Math.abs(p.v)), 0.0001);
      const inset = 0.12;
      const uvScale = (0.5 - inset) / maxAbs;
      const uvOf = (i) => [0.5 + proj[i].u * uvScale, 0.5 + proj[i].v * uvScale];

      // Triangle-fan from vertex 0
      for (let i = 1; i < verts.length - 1; i++) {
        positions.push(verts[0].x, verts[0].y, verts[0].z);
        positions.push(verts[i].x, verts[i].y, verts[i].z);
        positions.push(verts[i + 1].x, verts[i + 1].y, verts[i + 1].z);
        const [u0, v0] = uvOf(0);
        const [u1, v1] = uvOf(i);
        const [u2, v2] = uvOf(i + 1);
        uvs.push(u0, v0, u1, v1, u2, v2);
      }

      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(new Float32Array(positions), 3));
      g.setAttribute('uv',       new THREE.BufferAttribute(new Float32Array(uvs), 2));
      g.computeVertexNormals();

      const m = new THREE.MeshStandardMaterial({
        map: texture,
        roughness: 0.55,
        metalness: 0.1,
        side: THREE.DoubleSide,
      });

      const faceMesh = new THREE.Mesh(g, m);
      group.add(faceMesh);
    });

    return group;
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
    this.diceSides = diceData.sides && typeof diceData.sides === 'number' ? diceData.sides : null;
    this.diceFaceValues = null;  // populated by createPolyhedralMesh

    // Routing:
    //   - shape:'polyhedral' + sides:N (4/6/8/10/12) → unified polyhedral builder
    //   - legacy d6 variants (card faces with custom text, defense block textures,
    //     red-enemy cube) stay on createD6Mesh
    //   - everything else (including unflagged d20) → createD20Mesh
    if (diceData.shape === 'polyhedral' && [4, 6, 8, 10, 12].includes(diceData.sides)) {
      this.mesh = this.createPolyhedralMesh(diceData);
    } else if (diceData.type === 'd6-defense' || diceData.type.startsWith('d6-enemy') || diceData.type === 'd6-card') {
      this.mesh = this.createD6Mesh(diceData);
    } else {
      // Default to D20
      this.mesh = this.createD20Mesh(diceData);
    }

    this.scene.add(this.mesh);
  }

  /**
   * Roll the dice with animation.
   * @param {Object} diceData - Dice data from dice system
   * @param {number} result - Pre-determined result from dice system
   * @param {Function} callback - Callback when roll completes
   * @param {Object} [options] - Optional flags
   * @param {boolean} [options.skipAnimation=false] - If true, snap the mesh
   *   to the target face's rotation immediately, no spin animation. Used by
   *   the dice tray when re-rendering an already-rolled die so it doesn't
   *   replay the roll on every UI tick.
   */
  rollDice(diceData, result, callback, options = {}) {
    if (this.isRolling) {
      console.warn('Dice is already rolling');
      return;
    }

    // Mesh hasn't been built yet (createDice never ran, or dispose() cleared it).
    // Without it there's no rotation to interpolate from, so just deliver the
    // result and bail out.
    if (!this.mesh) {
      this.hasRolled = true;
      if (callback) callback(result);
      return;
    }

    // Snap into place without animation — caller is just re-mounting a die
    // whose value we've already shown the player.
    if (options.skipAnimation) {
      this.hasRolled = true;
      const targetRotation = this.calculateFaceRotation(result);
      if (this.mesh) {
        this.mesh.rotation.set(targetRotation.x, targetRotation.y, targetRotation.z);
      }
      if (callback) callback(result);
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
      // Bail if dispose() ran (or createDice swapped mesh) while we were queued
      if (!this.mesh || !this.scene) {
        this.isRolling = false;
        this.rollCallback = null;
        return;
      }
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
    if (!this.mesh) {
      if (typeof callback === 'function') callback();
      return;
    }
    const jumpHeight = 1.5;
    const jumpDuration = 300;
    const startY = this.mesh.position.y;
    const startTime = Date.now();

    const jump = () => {
      if (!this.mesh) return;
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
    let faceIndex;

    if (this.diceFaceValues) {
      // Polyhedral dice (d4/d6/d8/d10/d12) — face values are assigned during
      // mesh build using the opposites-sum-to-N+1 convention. Look up the
      // mesh index where this value lives.
      faceIndex = this.diceFaceValues.indexOf(faceNumber);
    } else if (this.diceType === 'd6-defense' || this.diceType.startsWith('d6-enemy') || this.diceType === 'd6-card') {
      // Legacy d6: face index = value - 1
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

    return { x: euler.x, y: euler.y, z: euler.z };
  }

  /**
   * Animation loop
   */
  animate() {
    this.animationId = requestAnimationFrame(() => this.animate());

    // Slow idle rotation when not rolling, not being dragged, and hasn't been rolled yet
    if (!this.isRolling && !this.hasRolled && !this.isDraggingUser && this.mesh) {
      this.mesh.rotation.x += 0.002;
      this.mesh.rotation.y += 0.003;
    }

    if (this.renderer && this.scene && this.camera) {
      this.renderer.render(this.scene, this.camera);
    }
  }

  /**
   * Enable click-drag rotation in place. Used by the dice tray modal so the
   * player can inspect a die from every angle. Pauses idle auto-rotation
   * while the user is dragging. Idempotent — safe to call multiple times,
   * the second call replaces the previous listeners.
   *
   * No-op if a roll animation is in progress (the rolling sequence owns the
   * rotation until it completes).
   */
  enableDragRotate() {
    if (!this.container || !this.renderer) return;
    if (this._dragHandlers) this.disableDragRotate();

    const el = this.renderer.domElement;
    el.style.pointerEvents = 'auto';
    el.style.cursor = 'grab';

    let dragging = false;
    let lastX = 0, lastY = 0;

    const onDown = (e) => {
      if (this.isRolling) return;
      dragging = true;
      this.isDraggingUser = true;
      lastX = e.clientX;
      lastY = e.clientY;
      el.style.cursor = 'grabbing';
      e.preventDefault();
    };
    const onMove = (e) => {
      if (!dragging || !this.mesh) return;
      const dx = e.clientX - lastX;
      const dy = e.clientY - lastY;
      lastX = e.clientX;
      lastY = e.clientY;
      // Pixel→radian scale; tuned so a full container width gives ~1.5 rad
      const k = 0.01;
      this.mesh.rotation.y += dx * k;
      this.mesh.rotation.x += dy * k;
    };
    const onUp = () => {
      if (!dragging) return;
      dragging = false;
      this.isDraggingUser = false;
      el.style.cursor = 'grab';
    };

    el.addEventListener('mousedown', onDown);
    window.addEventListener('mousemove', onMove);
    window.addEventListener('mouseup', onUp);
    // Also handle pointer leaving the window mid-drag
    window.addEventListener('mouseleave', onUp);

    this._dragHandlers = { el, onDown, onMove, onUp };
  }

  /** Tear down drag listeners installed by enableDragRotate. */
  disableDragRotate() {
    if (!this._dragHandlers) return;
    const { el, onDown, onMove, onUp } = this._dragHandlers;
    el.removeEventListener('mousedown', onDown);
    window.removeEventListener('mousemove', onMove);
    window.removeEventListener('mouseup', onUp);
    window.removeEventListener('mouseleave', onUp);
    el.style.cursor = '';
    el.style.pointerEvents = 'none';
    this._dragHandlers = null;
    this.isDraggingUser = false;
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
    // Tear down any interactive listeners (drag-rotate, etc.) first
    this.disableDragRotate();

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
