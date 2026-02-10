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

// ===== MODAL FUNCTIONS =====

function createGameModal(content) {
  const existingModal = document.getElementById('game-modal');
  if (existingModal) existingModal.remove();

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
    z-index: 10000;
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
  const modal = document.getElementById('game-modal');
  if (modal) {
    modal.style.animation = 'fadeOut 0.3s';
    setTimeout(() => modal.remove(), 300);
  }

  // Clean up combat tooltip if it exists
  const combatTooltip = document.getElementById('combat-item-tooltip');
  if (combatTooltip) {
    combatTooltip.remove();
  }
}

// Export modal functions globally
window.createGameModal = createGameModal;
window.closeGameModal = closeGameModal;
