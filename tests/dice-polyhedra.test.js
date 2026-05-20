/**
 * Geometry tests for the polyhedral dice mesh builder in js/dice-renderer.js.
 *
 * The file expects THREE.* from a CDN script tag. Vitest runs in jsdom with
 * no THREE on the global, so we stub a minimal THREE.Vector3 that supports
 * the methods _buildPolyhedronFaceData / _assignFaceValues use, then load
 * the renderer file just to pull those two helpers (not the class — the
 * class needs WebGL/CanvasTexture which jsdom can't provide).
 *
 * What we verify per die size:
 *   - correct face count (4 / 6 / 8 / 10 / 12)
 *   - per-face vertex count (3 for d4/d8, 4 for d6/d10, 5 for d12)
 *   - every face normal is unit length
 *   - every face normal points outward (positive dot with its centroid)
 *   - opposite-face detection works for d6/d8/d10/d12 (d4 has no opposites)
 *   - _assignFaceValues produces values 1..N where opposite pairs sum to N+1
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const ROOT = resolve(__filename, '..', '..');

// Minimal THREE.Vector3 stub — covers every method used by the polyhedron helpers.
class V3 {
  constructor(x = 0, y = 0, z = 0) { this.x = x; this.y = y; this.z = z; }
  set(x, y, z) { this.x = x; this.y = y; this.z = z; return this; }
  clone() { return new V3(this.x, this.y, this.z); }
  add(v) { this.x += v.x; this.y += v.y; this.z += v.z; return this; }
  subVectors(a, b) { this.x = a.x - b.x; this.y = a.y - b.y; this.z = a.z - b.z; return this; }
  crossVectors(a, b) {
    const x = a.y * b.z - a.z * b.y;
    const y = a.z * b.x - a.x * b.z;
    const z = a.x * b.y - a.y * b.x;
    this.x = x; this.y = y; this.z = z;
    return this;
  }
  dot(v) { return this.x * v.x + this.y * v.y + this.z * v.z; }
  length() { return Math.sqrt(this.dot(this)); }
  multiplyScalar(s) { this.x *= s; this.y *= s; this.z *= s; return this; }
  negate() { this.x = -this.x; this.y = -this.y; this.z = -this.z; return this; }
  normalize() {
    const l = this.length() || 1;
    this.x /= l; this.y /= l; this.z /= l;
    return this;
  }
}

beforeAll(() => {
  globalThis.THREE = { Vector3: V3 };

  // Read dice-renderer.js and extract just the two top-level helpers we need
  // to test. Indirect-evaling the whole file would also bring in the class,
  // which references THREE.Scene / WebGLRenderer / CanvasTexture that jsdom
  // can't satisfy — but those are inside class methods so they don't execute
  // until called. Just eval the whole file in global scope; class methods
  // never run from these tests.
  const src = readFileSync(resolve(ROOT, 'js/dice-renderer.js'), 'utf-8');
  // The helpers are `function _buildPolyhedronFaceData(...)` and
  // `function _assignFaceValues(...)` declared with `function`, so they
  // bind to globalThis under indirect eval.
  (0, eval)(src);
});

const SUPPORTED = [
  { sides: 4,  vertsPerFace: 3, hasOpposites: false },
  { sides: 6,  vertsPerFace: 4, hasOpposites: true },
  { sides: 8,  vertsPerFace: 3, hasOpposites: true },
  { sides: 10, vertsPerFace: 4, hasOpposites: true },
  { sides: 12, vertsPerFace: 5, hasOpposites: true },
];

describe('_buildPolyhedronFaceData', () => {
  for (const { sides, vertsPerFace, hasOpposites } of SUPPORTED) {
    describe(`d${sides}`, () => {
      let faceData;
      beforeAll(() => {
        faceData = globalThis._buildPolyhedronFaceData(sides, 1);
      });

      it(`has exactly ${sides} faces`, () => {
        expect(faceData.faces.length).toBe(sides);
      });

      it(`each face has ${vertsPerFace} vertices`, () => {
        for (const f of faceData.faces) {
          expect(f.vertices.length).toBe(vertsPerFace);
        }
      });

      it('every face normal is unit length', () => {
        for (const f of faceData.faces) {
          const n = f.normal;
          const len = Math.sqrt(n.x * n.x + n.y * n.y + n.z * n.z);
          expect(len).toBeCloseTo(1, 5);
        }
      });

      it('every face normal points outward (positive dot with centroid)', () => {
        for (const f of faceData.faces) {
          const dot = f.normal.dot(f.centroid);
          // Strictly positive — face is on the surface, normal goes away from origin
          expect(dot).toBeGreaterThan(0);
        }
      });

      if (hasOpposites) {
        it('every face has exactly one anti-parallel opposite', () => {
          for (let i = 0; i < faceData.faces.length; i++) {
            const ni = faceData.faces[i].normal;
            const opposites = [];
            for (let j = 0; j < faceData.faces.length; j++) {
              if (i === j) continue;
              if (faceData.faces[j].normal.dot(ni) < -0.99) opposites.push(j);
            }
            expect(opposites.length, `d${sides} face ${i} opposite count`).toBe(1);
          }
        });
      } else {
        it('no two faces are anti-parallel (tetrahedron has no opposites)', () => {
          for (let i = 0; i < faceData.faces.length; i++) {
            for (let j = i + 1; j < faceData.faces.length; j++) {
              const dot = faceData.faces[i].normal.dot(faceData.faces[j].normal);
              expect(dot).toBeGreaterThan(-0.9);
            }
          }
        });
      }

      it('all face centroids are at roughly the same distance from origin', () => {
        // Inscribed-sphere radius — should be identical for all faces of a
        // regular polyhedron. d10 (pentagonal trapezohedron) isn't regular
        // but its top-hemisphere faces and bottom-hemisphere faces each form
        // a single inscribed-radius group, so checking equal-within-tolerance
        // per hemisphere is enough. We use a loose tolerance to cover d10.
        const dists = faceData.faces.map(f => f.centroid.length());
        const minD = Math.min(...dists);
        const maxD = Math.max(...dists);
        // d10 has identical face shape so equal radius; tolerance generous
        // enough that any catastrophic vertex error would fail this.
        expect(maxD - minD).toBeLessThan(0.05);
      });
    });
  }
});

describe('_assignFaceValues — real-die numbering convention', () => {
  for (const { sides, hasOpposites } of SUPPORTED) {
    describe(`d${sides}`, () => {
      let faceData, values;
      beforeAll(() => {
        faceData = globalThis._buildPolyhedronFaceData(sides, 1);
        values = globalThis._assignFaceValues(faceData, sides);
      });

      it(`uses every value 1..${sides} exactly once`, () => {
        const sorted = values.slice().sort((a, b) => a - b);
        const expected = Array.from({ length: sides }, (_, i) => i + 1);
        expect(sorted).toEqual(expected);
      });

      if (hasOpposites) {
        it(`opposite faces sum to ${sides + 1}`, () => {
          for (let i = 0; i < sides; i++) {
            // Find the anti-parallel face by normal
            let opp = -1;
            for (let j = 0; j < sides; j++) {
              if (i === j) continue;
              if (faceData.faces[j].normal.dot(faceData.faces[i].normal) < -0.99) {
                opp = j; break;
              }
            }
            expect(opp).not.toBe(-1);
            expect(values[i] + values[opp]).toBe(sides + 1);
          }
        });
      }
    });
  }
});

describe('radius scaling', () => {
  it('d6 vertices end up at the requested circumradius', () => {
    const r = 2.5;
    const fd = globalThis._buildPolyhedronFaceData(6, r);
    // For a cube, every vertex is at distance r from center
    for (const f of fd.faces) {
      for (const v of f.vertices) {
        const d = Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
        expect(d).toBeCloseTo(r, 4);
      }
    }
  });

  it('d8 vertices end up at the requested circumradius', () => {
    const r = 1.7;
    const fd = globalThis._buildPolyhedronFaceData(8, r);
    for (const f of fd.faces) {
      for (const v of f.vertices) {
        const d = Math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
        expect(d).toBeCloseTo(r, 4);
      }
    }
  });
});

describe('error cases', () => {
  it('throws on unsupported side counts', () => {
    expect(() => globalThis._buildPolyhedronFaceData(7, 1)).toThrow(/Unsupported/);
    expect(() => globalThis._buildPolyhedronFaceData(100, 1)).toThrow(/Unsupported/);
  });
});
