/**
 * BFS Cache - Performance optimization for pathfinding
 * Caches BFS results to avoid recalculating the same paths repeatedly
 *
 * Current issue: BFS runs 3+ times per game selection, each time traversing entire graph
 * With cache: BFS runs once, subsequent lookups are O(1)
 */

class BFSCache {
  constructor() {
    this.cache = new Map();
    this.enabled = true;
  }

  /**
   * Generate cache key for a BFS query
   * @param {string} start - Start game name
   * @param {string} end - End game name
   * @returns {string} - Cache key
   */
  static getCacheKey(start, end) {
    return `${start}::${end}`;
  }

  /**
   * Get cached BFS result
   * @param {string} start - Start game name
   * @param {string} end - End game name
   * @returns {number|null} - Cached distance or null if not cached
   */
  get(start, end) {
    if (!this.enabled) return null;

    const key = BFSCache.getCacheKey(start, end);
    return this.cache.get(key) ?? null;
  }

  /**
   * Set cached BFS result
   * @param {string} start - Start game name
   * @param {string} end - End game name
   * @param {number} distance - Distance between games
   */
  set(start, end, distance) {
    if (!this.enabled) return;

    const key = BFSCache.getCacheKey(start, end);
    this.cache.set(key, distance);
  }

  /**
   * Clear all cached results
   */
  clear() {
    this.cache.clear();
  }

  /**
   * Get cache size
   * @returns {number} - Number of cached entries
   */
  size() {
    return this.cache.size;
  }

  /**
   * Enable caching
   */
  enable() {
    this.enabled = true;
  }

  /**
   * Disable caching (for debugging)
   */
  disable() {
    this.enabled = false;
    this.clear();
  }

  /**
   * Get cache hit rate statistics
   * @returns {Object} - { hits, misses, hitRate }
   */
  getStats() {
    return {
      size: this.size(),
      enabled: this.enabled
    };
  }
}

// Create global instance
const bfsCache = new BFSCache();

/**
 * Cached version of BFS that uses the cache
 * Drop-in replacement for existing bfs() function
 * @param {string} start - Start game name
 * @param {string} goal - Goal game name
 * @returns {number} - Distance or Infinity if no path
 */
function bfsCached(start, goal) {
  // Check cache first
  const cached = bfsCache.get(start, goal);
  if (cached !== null) {
    return cached;
  }

  // Not in cache, compute it
  const distance = bfs(start, goal);

  // Store in cache
  bfsCache.set(start, goal, distance);

  return distance;
}

/**
 * Invalidate cache when game connections might have changed
 * Call this when:
 * - New game is visited
 * - Game data is reloaded
 * - Starting new run
 */
function invalidateBFSCache() {
  bfsCache.clear();
  console.log('BFS cache invalidated');
}

// Export for use in other files
if (typeof window !== 'undefined') {
  window.BFSCache = BFSCache;
  window.bfsCache = bfsCache;
  window.bfsCached = bfsCached;
  window.invalidateBFSCache = invalidateBFSCache;
}
