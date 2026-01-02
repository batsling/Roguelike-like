/**
 * Storage Utility - Safe localStorage wrapper with error handling
 * Handles quota exceeded, parse errors, and provides versioning support
 */

class GameStorage {
  static VERSION = 2;

  /**
   * Save data to localStorage with error handling
   * @param {string} key - Storage key
   * @param {*} data - Data to save (will be JSON stringified)
   * @returns {Object} - { success: boolean, error?: string }
   */
  static save(key, data) {
    try {
      const payload = JSON.stringify(data);
      localStorage.setItem(key, payload);
      return { success: true };
    } catch (error) {
      console.error(`Failed to save to localStorage (${key}):`, error);

      if (error.name === 'QuotaExceededError') {
        return {
          success: false,
          error: 'Storage quota exceeded. Try clearing old saves.'
        };
      }

      return {
        success: false,
        error: `Failed to save: ${error.message}`
      };
    }
  }

  /**
   * Load data from localStorage with error handling
   * @param {string} key - Storage key
   * @param {*} defaultValue - Value to return if key doesn't exist or error occurs
   * @returns {*} - Parsed data or defaultValue
   */
  static load(key, defaultValue = null) {
    try {
      const raw = localStorage.getItem(key);

      if (raw === null) {
        return defaultValue;
      }

      return JSON.parse(raw);
    } catch (error) {
      console.error(`Failed to load from localStorage (${key}):`, error);
      return defaultValue;
    }
  }

  /**
   * Remove item from localStorage
   * @param {string} key - Storage key
   * @returns {boolean} - Success status
   */
  static remove(key) {
    try {
      localStorage.removeItem(key);
      return true;
    } catch (error) {
      console.error(`Failed to remove from localStorage (${key}):`, error);
      return false;
    }
  }

  /**
   * Clear all localStorage
   * @returns {boolean} - Success status
   */
  static clear() {
    try {
      localStorage.clear();
      return true;
    } catch (error) {
      console.error('Failed to clear localStorage:', error);
      return false;
    }
  }

  /**
   * Check if a key exists in localStorage
   * @param {string} key - Storage key
   * @returns {boolean} - Whether key exists
   */
  static has(key) {
    return localStorage.getItem(key) !== null;
  }

  /**
   * Get storage size in bytes (approximate)
   * @returns {number} - Approximate storage size
   */
  static getSize() {
    let total = 0;
    for (let key in localStorage) {
      if (localStorage.hasOwnProperty(key)) {
        total += localStorage[key].length + key.length;
      }
    }
    return total;
  }

  /**
   * Get storage size in human-readable format
   * @returns {string} - Size string (e.g., "2.5 KB")
   */
  static getSizeFormatted() {
    const bytes = this.getSize();

    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(2)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  }
}

// Export for use in other files
if (typeof window !== 'undefined') {
  window.GameStorage = GameStorage;
}
