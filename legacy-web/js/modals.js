/**
 * MODALS.JS - Modal Creation and Management
 *
 * Responsibilities:
 * - Creating game modals with standard styling
 * - Closing modals with fade animation
 * - Managing modal lifecycle
 *
 * Key Functions:
 * - createGameModal(content) - Creates and displays a modal with given HTML content
 * - closeGameModal() - Closes the current game modal with animation
 *
 * Z-Index Usage:
 * - Modal backdrop: 10000 (Layer 4 - Modals)
 * - Modal content is inside backdrop, inherits stacking context
 * - See main.js for full z-index layering system documentation
 */

// ===== TOOLTIP CLEANUP =====

// All known tooltip/hover-overlay element IDs across the app.
// Called whenever the screen changes so stale tooltips don't linger.
const TOOLTIP_IDS = [
  'item-tooltip',
  'game-tooltip',
  'loot-tooltip',
  'location-hover-tooltip',
  'combat-item-tooltip',
  'combat-status-tooltip',
  'card-name-tooltip',
  'starting-item-tip',
  'collection-item-tip',
];

function hideAllTooltips() {
  TOOLTIP_IDS.forEach(id => {
    const el = document.getElementById(id);
    if (el) el.style.display = 'none';
  });
  // Also hide the combat status tooltip via its own function if available
  if (typeof hideStatusTooltip === 'function') hideStatusTooltip();
}

// ===== MODAL FUNCTIONS =====

function createGameModal(content) {
  hideAllTooltips();

  const existingModal = document.getElementById('game-modal');
  if (existingModal) {
    // If the modal being torn down hosted live event dice, release their
    // WebGL contexts before yanking the DOM — otherwise the renderers leak
    // and we eventually trip "Too many active WebGL contexts".
    if (existingModal.querySelector('[id^="ev-die-"]') &&
        typeof window._disposeEventRenderers === 'function') {
      window._disposeEventRenderers();
    }
    existingModal.remove();
  }

  const modal = document.createElement('div');
  modal.id = 'game-modal';
  modal.style.cssText = `
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0,0,0,0.5);
    display: flex;
    justify-content: center;
    align-items: flex-start;
    padding-top: 30px;
    z-index: 500;
    animation: fadeIn 0.3s;
  `;

  const modalContent = document.createElement('div');
  modalContent.className = 'modal-content';
  modalContent.style.cssText = `
    background: #2a2420;
    padding: 30px;
    border-radius: 12px;
    max-width: 1400px;
    width: 95vw;
    max-height: 90vh;
    overflow-y: auto;
    color: #e6d5b8;
    box-shadow: 0 10px 40px rgba(0,0,0,0.8);
    border: 2px solid #cc6600;
  `;

  modalContent.innerHTML = content;
  modal.appendChild(modalContent);
  document.body.appendChild(modal);

  return modal;
}

function closeGameModal() {
  hideAllTooltips();

  // Cancel any in-progress card drag so the clone doesn't linger after combat closes
  const dragClone = document.getElementById('combat-drag-clone');
  if (dragClone) dragClone.remove();
  if (typeof window.cancelCombatDrag === 'function') window.cancelCombatDrag();

  const modal = document.getElementById('game-modal');
  if (modal) {
    // Same WebGL-context cleanup as createGameModal — dispose live event dice
    // before the fadeOut + remove, so contexts are released immediately.
    if (modal.querySelector('[id^="ev-die-"]') &&
        typeof window._disposeEventRenderers === 'function') {
      window._disposeEventRenderers();
    }
    modal.style.animation = 'fadeOut 0.3s';
    setTimeout(() => modal.remove(), 300);
  }

  // Remove combat tooltip entirely (it gets recreated when needed)
  const combatTooltip = document.getElementById('combat-item-tooltip');
  if (combatTooltip) {
    combatTooltip.remove();
  }
}

// ===== SECONDARY (PANEL) OVERLAY =====
// Used by Deck, Dice Tray, and Spells when a primary modal is already open.
// Creates a separate overlay with a higher z-index so it layers on top without
// destroying the primary modal (e.g. an in-progress event screen).

function createPanelOverlay(content) {
  hideAllTooltips();
  const existing = document.getElementById('panel-overlay');
  if (existing) existing.remove();

  const overlay = document.createElement('div');
  overlay.id = 'panel-overlay';
  overlay.style.cssText = `
    position: fixed;
    top: 0; left: 0; right: 0; bottom: 0;
    background: rgba(0,0,0,0.72);
    display: flex;
    justify-content: center;
    align-items: flex-start;
    padding-top: 30px;
    z-index: 20000;
    animation: fadeIn 0.3s;
  `;

  const inner = document.createElement('div');
  inner.className = 'panel-overlay-content';
  inner.style.cssText = `
    background: #2a2420;
    padding: 30px;
    border-radius: 12px;
    max-width: 1400px;
    width: 95vw;
    max-height: 90vh;
    overflow-y: auto;
    color: #e6d5b8;
    box-shadow: 0 10px 40px rgba(0,0,0,0.9);
    border: 2px solid #cc6600;
  `;
  inner.innerHTML = content;
  overlay.appendChild(inner);
  document.body.appendChild(overlay);

  // Click backdrop to close
  overlay.addEventListener('click', e => { if (e.target === overlay) closePanelOverlay(); });

  return overlay;
}

function closePanelOverlay() {
  const overlay = document.getElementById('panel-overlay');
  if (overlay) {
    overlay.style.animation = 'fadeOut 0.3s';
    setTimeout(() => overlay.remove(), 300);
  }
}

// Decide whether to open content as a panel overlay (when a modal is already open)
// or as the primary game modal (when nothing is open).
function openDeckDiceSpellsModal(content, usePanel) {
  if (usePanel) {
    createPanelOverlay(content);
  } else {
    createGameModal(content);
  }
}

// Export modal functions globally
window.createGameModal = createGameModal;
window.closeGameModal = closeGameModal;
window.hideAllTooltips = hideAllTooltips;
window.createPanelOverlay = createPanelOverlay;
window.closePanelOverlay = closePanelOverlay;
window.openDeckDiceSpellsModal = openDeckDiceSpellsModal;
