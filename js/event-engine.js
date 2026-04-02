/**
 * EVENT-ENGINE.JS
 *
 * Handles the new pre-combat event system:
 * - Reads events from EVENTS_DATA (events-data.js)
 * - Displays nested choice modals
 * - Performs stat-based 4-outcome rolls (crit_bad / bad / good / crit_good)
 * - Applies effects (heal, damage, gold, curse, item, combat_status)
 * - Triggers combat after the event resolves
 *
 * Overrides window.showEventModal defined in main.js.
 */

console.log('✅ EVENT-ENGINE.JS loaded');

// ─────────────────────────────────────────────────────────────────────────────
// STAT CHECK ROLL
// Roll 1d20. Natural 1 = always crit_bad. Natural 20 = always crit_good.
// For rolls 2-19 the outcome zone shifts based on stat value (higher = better).
// Every outcome always has at least 5% chance regardless of stat.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * @param {string} statName - 'strength'|'dexterity'|'intelligence'|'charisma'
 * @returns {{ result: string, roll: number, statValue: number }}
 */
function performStatCheck(statName) {
  // Get current stat value from globals (set in main.js)
  const statMap = {
    strength:     typeof strength     !== 'undefined' ? strength     : 0,
    dexterity:    typeof dexterity    !== 'undefined' ? dexterity    : 0,
    intelligence: typeof intelligence !== 'undefined' ? intelligence : 0,
    charisma:     typeof charisma     !== 'undefined' ? charisma     : 0
  };
  const statValue = statMap[statName.toLowerCase()] || 0;

  const roll = Math.floor(Math.random() * 20) + 1;

  // Natural extremes — always a chance regardless of stat
  if (roll === 1)  return { result: 'crit_bad',  roll, statValue };
  if (roll === 20) return { result: 'crit_good', roll, statValue };

  // Rolls 2-19: thresholds shift with stat, but each zone always has ≥1 face
  // Effective bonus caps at 8 to prevent zones from collapsing
  const bonus = Math.min(statValue, 8);

  // critBad zone top: rolls 2 to critBadTop
  const critBadTop = Math.max(2, 5 - Math.floor(bonus * 0.5));
  // bad zone top: critBadTop+1 to badTop
  const badTop     = Math.max(critBadTop + 3, 12 - bonus);
  // good zone top: badTop+1 to goodTop  (rolls above = crit_good, but nat20 is already handled)
  const goodTop    = Math.min(19, 18 - Math.floor(bonus * 0.2));

  if (roll <= critBadTop) return { result: 'crit_bad',  roll, statValue };
  if (roll <= badTop)     return { result: 'bad',        roll, statValue };
  if (roll <= goodTop)    return { result: 'good',       roll, statValue };
  return                         { result: 'crit_good',  roll, statValue };
}

// ─────────────────────────────────────────────────────────────────────────────
// EFFECT APPLICATION
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Apply a list of event effects to the player.
 * @param {Array} effects
 * @returns {string[]} Human-readable lines describing what happened
 */
function applyEventEffects(effects) {
  const lines = [];

  for (const effect of effects) {
    switch (effect.type) {

      case 'heal': {
        const amount = Math.min(effect.value, maxHealth - health);
        if (amount > 0) {
          health = Math.min(maxHealth, health + effect.value);
          if (typeof gameState !== 'undefined') gameState.health = health;
          if (typeof updateHealthDisplay === 'function') updateHealthDisplay();
          if (typeof updateTopBar === 'function') updateTopBar();
          lines.push(`+${effect.value} HP`);
        }
        break;
      }

      case 'damage': {
        let dmg = effect.value;
        if (typeof calculateDamageReduction === 'function') dmg = calculateDamageReduction(dmg);
        health = Math.max(0, health - dmg);
        if (typeof gameState !== 'undefined') gameState.health = health;
        if (typeof updateHealthDisplay === 'function') updateHealthDisplay();
        if (typeof updateTopBar === 'function') updateTopBar();
        lines.push(`-${dmg} HP`);
        break;
      }

      case 'gold': {
        if (effect.value > 0) {
          gold = (gold || 0) + effect.value;
          lines.push(`+${effect.value} Gold`);
        } else {
          const lost = Math.min(gold || 0, Math.abs(effect.value));
          gold = Math.max(0, (gold || 0) + effect.value);
          lines.push(`-${lost} Gold`);
        }
        if (typeof gameState !== 'undefined') gameState.gold = gold;
        if (typeof updateTopBar === 'function') updateTopBar();
        break;
      }

      case 'curse': {
        let curseName = effect.value;
        if (curseName === 'random') {
          const pool = typeof curses !== 'undefined' ? curses : (typeof CURSES_DATA !== 'undefined' ? CURSES_DATA : []);
          if (pool.length > 0) {
            curseName = pool[Math.floor(Math.random() * pool.length)].name;
          }
        }
        if (curseName && curseName !== 'random') {
          if (typeof StateMutator !== 'undefined' && StateMutator.addCurse) {
            StateMutator.addCurse(curseName, { notify: false });
          } else if (Array.isArray(gameState?.activeCurses)) {
            const pool = typeof curses !== 'undefined' ? curses : [];
            const curseData = pool.find(c => c.name === curseName);
            if (curseData) gameState.activeCurses.push({ ...curseData });
          }
          if (typeof updateCursesDisplay === 'function') updateCursesDisplay();
          if (typeof createNotification === 'function') {
            createNotification(`Cursed: ${curseName}`, '#e74c3c', '😈');
          }
          lines.push(`Cursed: ${curseName}`);
        }
        break;
      }

      case 'remove_curse': {
        const activeCurses = gameState?.activeCurses;
        if (Array.isArray(activeCurses) && activeCurses.length > 0) {
          // Pick the most recently added curse (or random)
          let idx;
          if (effect.value === 'random') {
            idx = Math.floor(Math.random() * activeCurses.length);
          } else {
            idx = activeCurses.findIndex(c => c.name === effect.value);
          }
          if (idx >= 0) {
            const removed = activeCurses.splice(idx, 1)[0];
            if (typeof updateCursesDisplay === 'function') updateCursesDisplay();
            if (typeof createNotification === 'function') {
              createNotification(`Curse lifted: ${removed.name}`, '#2ecc71', '✨');
            }
            lines.push(`Curse removed: ${removed.name}`);
          } else {
            lines.push('No curse to remove');
          }
        } else {
          lines.push('No curse to remove');
        }
        break;
      }

      case 'item': {
        // Grant a random item from items array
        const pool = typeof items !== 'undefined' ? items.filter(i => i.rarity && i.rarity !== 'N/A') : [];
        if (pool.length > 0) {
          const item = pool[Math.floor(Math.random() * pool.length)];
          if (typeof acquireItem === 'function') acquireItem(item);
          lines.push(`Item: ${item.name}`);
        }
        break;
      }

      case 'combat_status': {
        // Queue a combat status to be applied at the start of the next combat
        if (!gameState.pendingCombatStatuses) gameState.pendingCombatStatuses = [];
        gameState.pendingCombatStatuses.push({ status: effect.status, stacks: effect.stacks || 1 });
        lines.push(`Start combat with ${effect.stacks || 1}× ${effect.status}`);
        break;
      }

      case 'none':
      default:
        break;
    }
  }

  if (typeof saveCurrentGame === 'function') saveCurrentGame();
  return lines;
}

// ─────────────────────────────────────────────────────────────────────────────
// MODAL HELPERS
// ─────────────────────────────────────────────────────────────────────────────

const OUTCOME_COLORS = {
  crit_bad:  '#e74c3c',
  bad:       '#e67e22',
  good:      '#2ecc71',
  crit_good: '#9b59b6'
};

const OUTCOME_LABELS = {
  crit_bad:  'Critical Failure',
  bad:       'Failure',
  good:      'Success',
  crit_good: 'Critical Success'
};

const STAT_ICONS = {
  strength:     '💪',
  dexterity:    '🤸',
  intelligence: '🧠',
  charisma:     '💬'
};

function _statLabel(stat) {
  return stat.charAt(0).toUpperCase() + stat.slice(1);
}

// ─────────────────────────────────────────────────────────────────────────────
// OUTCOME DISPLAY
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Render the outcome panel and apply effects.
 * Calls onContinue (which triggers combat) after player clicks Continue.
 */
function _showOutcome(outcome, onContinue, rollInfo) {
  const effectLines = applyEventEffects(outcome.effects || []);

  const rollHTML = rollInfo ? `
    <div style="
      display:inline-block;
      background:#1a1a2e;
      border:2px solid ${OUTCOME_COLORS[rollInfo.result]};
      border-radius:8px;
      padding:10px 20px;
      margin-bottom:16px;
      font-size:14px;
    ">
      ${STAT_ICONS[rollInfo.stat] || ''} <strong>${_statLabel(rollInfo.stat)}</strong>
      &nbsp;|&nbsp; Rolled <strong style="font-size:20px">${rollInfo.roll}</strong>
      &nbsp;(stat: ${rollInfo.statValue})
      &nbsp;→&nbsp; <span style="color:${OUTCOME_COLORS[rollInfo.result]};font-weight:bold">
        ${OUTCOME_LABELS[rollInfo.result]}
      </span>
    </div>
  ` : '';

  const effectsHTML = effectLines.length > 0 ? `
    <div style="
      background:#1a1a1a;
      border-radius:6px;
      padding:10px 16px;
      margin:12px 0;
      font-size:13px;
      color:#ddd;
      text-align:left;
      display:inline-block;
      min-width:160px;
    ">
      ${effectLines.map(l => `<div>• ${l}</div>`).join('')}
    </div>
  ` : '';

  const color = rollInfo ? OUTCOME_COLORS[rollInfo.result] : '#aaa';

  createGameModal(`
    <div style="text-align:center;padding:20px;max-width:560px;margin:0 auto;">
      ${rollHTML}
      <p style="color:#ddd;font-size:15px;line-height:1.6;margin:0 0 12px;">
        ${outcome.description}
      </p>
      ${effectsHTML}
      <div style="margin-top:20px;">
        <button id="event-continue-btn" style="
          padding:12px 36px;
          background:${color};
          border:none;border-radius:8px;
          color:#fff;font-weight:bold;font-size:15px;
          cursor:pointer;
          box-shadow:0 0 16px ${color}66;
          transition:opacity 0.2s;
        " onmouseover="this.style.opacity='0.85'" onmouseout="this.style.opacity='1'">
          Continue to Combat
        </button>
      </div>
    </div>
  `);

  document.getElementById('event-continue-btn').onclick = () => {
    closeGameModal();
    if (typeof onContinue === 'function') onContinue();
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT CHECK ANIMATION + RESULT
// ─────────────────────────────────────────────────────────────────────────────

function _runStatCheck(choice, event, onContinue) {
  const { result, roll, statValue } = performStatCheck(choice.stat);
  const outcome = choice.outcomes[result];
  const color   = OUTCOME_COLORS[result];

  // Brief animated roll display before showing outcome
  createGameModal(`
    <div style="text-align:center;padding:30px;max-width:460px;margin:0 auto;">
      <p style="color:#aaa;font-size:14px;margin-bottom:16px;">${choice.rollDescription || ''}</p>
      <div id="roll-display" style="
        font-size:64px;font-weight:bold;color:#fff;
        text-shadow:0 0 20px #fff;
        animation:rollSpin 0.6s ease-out forwards;
        margin:20px 0;
      ">${roll}</div>
      <style>
        @keyframes rollSpin {
          0%   { transform:scale(0.5) rotate(-10deg); opacity:0; }
          60%  { transform:scale(1.2) rotate(3deg);  opacity:1; }
          100% { transform:scale(1)   rotate(0deg);  opacity:1; }
        }
      </style>
      <div style="color:${color};font-size:18px;font-weight:bold;margin-bottom:8px;">
        ${OUTCOME_LABELS[result]}
      </div>
      <div style="color:#888;font-size:12px;">
        ${STAT_ICONS[choice.stat] || ''} ${_statLabel(choice.stat)} ${statValue > 0 ? '+' + statValue : ''}
      </div>
    </div>
  `);

  // After a short pause, show full outcome
  setTimeout(() => {
    _showOutcome(outcome, onContinue, { result, roll, statValue, stat: choice.stat });
  }, 1400);
}

// ─────────────────────────────────────────────────────────────────────────────
// CHOICE LIST RENDERING
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Show a set of choices from a node (top-level or sub-node).
 * @param {Object} event      - full event object
 * @param {Array}  choices    - array of choice objects to display
 * @param {string} description - description text for this node
 * @param {string} eventName  - display name
 * @param {Function} onContinue - called after event fully resolves
 */
function _showChoiceNode(event, choices, description, eventName, onContinue) {
  // Filter choices by requirements
  const visible = choices.filter(c => {
    if (!c.requires) return true;
    if (c.requires.gold !== undefined && (gold || 0) < c.requires.gold) return false;
    return true;
  });

  const choicesHTML = visible.map((choice, i) => {
    const isStatCheck = choice.type === 'stat_check';
    const icon = isStatCheck ? (STAT_ICONS[choice.stat] || '🎲') : '▶';
    const statHint = isStatCheck
      ? `<span style="color:#aaa;font-size:11px;margin-left:8px;">[${_statLabel(choice.stat)} check]</span>`
      : '';

    return `
      <button class="event-choice-btn" data-choice-idx="${i}" style="
        width:100%;
        padding:14px 18px;
        margin-bottom:10px;
        background:#2a2a2a;
        border:2px solid #444;
        border-left:5px solid ${isStatCheck ? '#e67e22' : '#3498db'};
        border-radius:8px;
        color:#eee;
        cursor:pointer;
        text-align:left;
        font-size:14px;
        line-height:1.4;
        transition:background 0.15s, transform 0.15s;
      "
      onmouseover="this.style.background='#353535';this.style.transform='translateX(4px)'"
      onmouseout="this.style.background='#2a2a2a';this.style.transform=''"
      >
        <span style="margin-right:8px;">${icon}</span>${choice.text}${statHint}
      </button>
    `;
  }).join('');

  createGameModal(`
    <div style="padding:24px;max-width:580px;margin:0 auto;">
      <h2 style="color:#9b59b6;margin-top:0;text-align:center;">
        ❓ ${eventName}
      </h2>
      <p style="color:#ccc;font-size:14px;line-height:1.6;margin-bottom:20px;text-align:center;">
        ${description}
      </p>
      <div>${choicesHTML}</div>
    </div>
  `);

  document.querySelectorAll('.event-choice-btn').forEach(btn => {
    btn.onclick = () => {
      const idx = parseInt(btn.dataset.choiceIdx);
      const choice = visible[idx];
      _handleChoice(event, choice, eventName, onContinue);
    };
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// CHOICE HANDLER
// ─────────────────────────────────────────────────────────────────────────────

function _handleChoice(event, choice, eventName, onContinue) {
  const resolveOutcome = (outcome) => {
    if (outcome.next) {
      // Navigate to a sub-node
      const node = event.nodes && event.nodes[outcome.next];
      if (node) {
        // Show outcome first, then sub-node
        _showOutcomeWithNext(outcome, () => {
          _showChoiceNode(event, node.choices, node.description, eventName, onContinue);
        }, null);
        return;
      }
    }
    // No next node — end of event, show outcome and go to combat
    _showOutcome(outcome, onContinue, null);
  };

  if (choice.type === 'stat_check') {
    _runStatCheck(choice, event, (result) => {
      // This path isn't used directly; stat check shows outcome inline
    });

    // Override: _runStatCheck shows result then calls _showOutcome directly
    // But we need to pass the correct outcome + onContinue
    // Re-implement inline for cleaner flow:
    const { result, roll, statValue } = performStatCheck(choice.stat);
    const outcome = choice.outcomes[result];
    const color   = OUTCOME_COLORS[result];

    createGameModal(`
      <div style="text-align:center;padding:30px;max-width:460px;margin:0 auto;">
        <p style="color:#aaa;font-size:14px;margin-bottom:16px;">${choice.rollDescription || 'Rolling...'}</p>
        <div style="
          font-size:64px;font-weight:bold;color:#fff;
          text-shadow:0 0 20px #fff;
          animation:eventRollSpin 0.6s ease-out forwards;
          margin:20px 0;
        ">${roll}</div>
        <style>
          @keyframes eventRollSpin {
            0%   { transform:scale(0.5) rotate(-10deg); opacity:0; }
            60%  { transform:scale(1.2) rotate(3deg);  opacity:1; }
            100% { transform:scale(1)   rotate(0deg);  opacity:1; }
          }
        </style>
        <div style="color:${color};font-size:18px;font-weight:bold;margin-bottom:8px;">
          ${OUTCOME_LABELS[result]}
        </div>
        <div style="color:#888;font-size:12px;">
          ${STAT_ICONS[choice.stat] || ''} ${_statLabel(choice.stat)} (${statValue > 0 ? '+' + statValue : statValue})
        </div>
      </div>
    `);

    setTimeout(() => {
      if (outcome.next) {
        const node = event.nodes && event.nodes[outcome.next];
        if (node) {
          _showOutcomeWithNext(
            outcome,
            () => _showChoiceNode(event, node.choices, node.description, eventName, onContinue),
            { result, roll, statValue, stat: choice.stat }
          );
          return;
        }
      }
      _showOutcome(outcome, onContinue, { result, roll, statValue, stat: choice.stat });
    }, 1400);

  } else {
    // Simple choice
    resolveOutcome(choice.outcome);
  }
}

/**
 * Show an outcome with a "Next" button that goes to a sub-node instead of combat.
 */
function _showOutcomeWithNext(outcome, onNext, rollInfo) {
  const effectLines = applyEventEffects(outcome.effects || []);

  const rollHTML = rollInfo ? `
    <div style="
      display:inline-block;background:#1a1a2e;
      border:2px solid ${OUTCOME_COLORS[rollInfo.result]};
      border-radius:8px;padding:10px 20px;margin-bottom:16px;font-size:14px;
    ">
      ${STAT_ICONS[rollInfo.stat] || ''} <strong>${_statLabel(rollInfo.stat)}</strong>
      &nbsp;|&nbsp; Rolled <strong style="font-size:20px">${rollInfo.roll}</strong>
      &nbsp;→&nbsp; <span style="color:${OUTCOME_COLORS[rollInfo.result]};font-weight:bold">
        ${OUTCOME_LABELS[rollInfo.result]}
      </span>
    </div>
  ` : '';

  const effectsHTML = effectLines.length > 0 ? `
    <div style="
      background:#1a1a1a;border-radius:6px;padding:10px 16px;
      margin:12px 0;font-size:13px;color:#ddd;
      text-align:left;display:inline-block;min-width:160px;
    ">
      ${effectLines.map(l => `<div>• ${l}</div>`).join('')}
    </div>
  ` : '';

  createGameModal(`
    <div style="text-align:center;padding:20px;max-width:560px;margin:0 auto;">
      ${rollHTML}
      <p style="color:#ddd;font-size:15px;line-height:1.6;margin:0 0 12px;">${outcome.description}</p>
      ${effectsHTML}
      <div style="margin-top:20px;">
        <button id="event-next-btn" style="
          padding:12px 36px;background:#3498db;
          border:none;border-radius:8px;color:#fff;font-weight:bold;font-size:15px;cursor:pointer;
        ">Continue</button>
      </div>
    </div>
  `);

  document.getElementById('event-next-btn').onclick = () => {
    if (typeof onNext === 'function') onNext();
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN ENTRY POINT — overrides showEventModal from main.js
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Pick a random event from EVENTS_DATA and run it.
 * After the event resolves, triggers combat via showCombatModal().
 */
function showEventModal(specificEvent) {
  const pool = typeof EVENTS_DATA !== 'undefined' ? EVENTS_DATA : [];
  if (pool.length === 0) {
    console.warn('EVENT-ENGINE: No events in EVENTS_DATA');
    // Fall through to combat immediately
    if (typeof showCombatModal === 'function') showCombatModal();
    return;
  }

  let event;
  if (specificEvent) {
    event = pool.find(e => e.id === specificEvent || e.name === specificEvent);
  }
  if (!event) {
    event = pool[Math.floor(Math.random() * pool.length)];
  }

  // Set phase
  if (typeof gameState !== 'undefined') {
    gameState.phase = 'event';
    gameState.currentEvent = event.name;
  }
  if (typeof updateInventory === 'function') updateInventory();

  // After event fully resolves → trigger combat (same logic as exploration.js)
  const onContinue = () => {
    if (window.useDiceCombat && typeof showDiceCombatModal === 'function') {
      showDiceCombatModal();
    } else if (typeof showCombatModal === 'function') {
      showCombatModal();
    }
  };

  _showChoiceNode(event, event.choices, event.description, event.name, onContinue);
}

// Register globally, overriding the version in main.js
window.showEventModal = showEventModal;
window.performStatCheck = performStatCheck;
window.applyEventEffects = applyEventEffects;
