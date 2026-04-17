/**
 * EVENT-ENGINE.JS
 *
 * Pre-combat event system with two-roll D20 mechanics:
 *   Roll 1 — Success Check:  D20 + stat vs rollDifficulty (11/13/15 by difficulty tier)
 *   Roll 2 — Critical Check: D20 vs 18 (18/19/20 = critical, no stat bonus)
 *   Luck:   10% per luck point for advantage on each roll (roll 2 dice, take best)
 *
 * UI flow per stat-check choice:
 *   1. Choice screen (event image + player image + options)
 *   2. Success roll screen — player clicks die(s) to roll
 *   3. Critical roll screen — player clicks die(s) to roll
 *   4. Outcome screen (description + effects + Continue to Combat)
 */

console.log('✅ EVENT-ENGINE.JS v2 loaded');

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

function _getCharName() {
  if (typeof PLAYER_CHARACTERS !== 'undefined' && typeof gameState !== 'undefined' && gameState.character) {
    const ch = PLAYER_CHARACTERS[gameState.character];
    if (ch && ch.name) return ch.name;
  }
  return 'The hero';
}

function _getPlayerImage() {
  if (typeof PLAYER_CHARACTERS !== 'undefined' && typeof gameState !== 'undefined' && gameState.character) {
    const ch = PLAYER_CHARACTERS[gameState.character];
    if (ch) return ch.fullImage || ch.icon || '';
  }
  return '';
}

function _fillName(text) {
  return (text || '').replace(/\{name\}/gi, _getCharName());
}

/** Get roll difficulty threshold based on current location difficulty. */
function _getRollDifficulty() {
  const diff = (typeof gameState !== 'undefined' && gameState.location && gameState.location.difficulty) || 'Easy';
  if (diff === 'Hard')   return 15;
  if (diff === 'Medium') return 13;
  return 11; // Easy
}

/** Return true if this roll gets advantage (luck-based). */
function _rollsAdvantage() {
  const luckVal = typeof luck !== 'undefined' ? luck : 0;
  return luckVal > 0 && Math.random() < luckVal * 0.1;
}

/** Roll a d20, with optional advantage (roll twice take best). */
function _rollD20(withAdvantage) {
  const a = Math.floor(Math.random() * 20) + 1;
  if (!withAdvantage) return { used: a, rolls: [a] };
  const b = Math.floor(Math.random() * 20) + 1;
  return { used: Math.max(a, b), rolls: [a, b] };
}

const OUTCOME_COLORS = {
  crit_bad:  '#e74c3c',
  bad:       '#e67e22',
  good:      '#2ecc71',
  crit_good: '#f1c40f'
};
const OUTCOME_LABELS = {
  crit_bad:  'Critical Failure',
  bad:       'Failure',
  good:      'Success',
  crit_good: 'Critical Success'
};
const STAT_ICONS = {
  strength: '💪', dexterity: '🤸', intelligence: '🧠', charisma: '💬'
};
function _statLabel(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

function _getStat(statName) {
  const map = {
    strength:     typeof strength     !== 'undefined' ? strength     : 0,
    dexterity:    typeof dexterity    !== 'undefined' ? dexterity    : 0,
    intelligence: typeof intelligence !== 'undefined' ? intelligence : 0,
    charisma:     typeof charisma     !== 'undefined' ? charisma     : 0
  };
  return map[statName.toLowerCase()] || 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// EFFECT APPLICATION
// ─────────────────────────────────────────────────────────────────────────────

function applyEventEffects(effects) {
  const lines = [];

  for (const effect of (effects || [])) {
    switch (effect.type) {

      case 'heal': {
        if (typeof health !== 'undefined' && typeof maxHealth !== 'undefined') {
          const gain = Math.min(effect.value, maxHealth - health);
          if (gain > 0) {
            health = Math.min(maxHealth, health + effect.value);
            if (typeof gameState !== 'undefined') gameState.health = health;
            if (typeof updateTopBar === 'function') updateTopBar();
            lines.push(`+${effect.value} HP`);
          }
        }
        break;
      }

      case 'damage': {
        let dmg = effect.value;
        if (typeof calculateDamageReduction === 'function') dmg = calculateDamageReduction(dmg);
        if (typeof health !== 'undefined') {
          health = Math.max(0, health - dmg);
          if (typeof gameState !== 'undefined') gameState.health = health;
          if (typeof updateTopBar === 'function') updateTopBar();
          lines.push(`-${dmg} HP`);
        }
        break;
      }

      case 'gold': {
        const g = effect.value || 0;
        if (typeof gold !== 'undefined') {
          if (g >= 0) {
            gold = (gold || 0) + g;
            lines.push(`+${g} Gold`);
          } else {
            const lost = Math.min(gold || 0, Math.abs(g));
            gold = Math.max(0, (gold || 0) + g);
            lines.push(`-${lost} Gold`);
          }
          if (typeof gameState !== 'undefined') gameState.gold = gold;
          if (typeof updateTopBar === 'function') updateTopBar();
        }
        break;
      }

      case 'gold_range': {
        const amount = Math.floor(Math.random() * (effect.max - effect.min + 1)) + effect.min;
        if (typeof gold !== 'undefined') {
          gold = (gold || 0) + amount;
          if (typeof gameState !== 'undefined') gameState.gold = gold;
          if (typeof updateTopBar === 'function') updateTopBar();
          lines.push(`+${amount} Gold`);
        }
        break;
      }

      case 'item_tagged': {
        const tag = (effect.tag || '').toLowerCase();
        const pool = (typeof items !== 'undefined' ? items : []).filter(i =>
          i.rarity && i.rarity !== 'N/A' &&
          Array.isArray(i.tags) && i.tags.some(t => t.toLowerCase() === tag)
        );
        if (pool.length > 0) {
          const item = pool[Math.floor(Math.random() * pool.length)];
          if (typeof acquireItem === 'function') acquireItem(item);
          lines.push(`Item: ${item.name}`);
        } else {
          lines.push(`No ${tag} item found`);
        }
        break;
      }

      case 'curse':
      case 'curse_difficulty': {
        let curseName = effect.value;
        if (effect.type === 'curse_difficulty') {
          const diff = (typeof gameState !== 'undefined' && gameState.location && gameState.location.difficulty) || 'Easy';
          const tier = diff === 'Hard' ? 'III' : diff === 'Medium' ? 'II' : 'I';
          curseName = `${effect.curseBase} ${tier}`;
        }
        if (curseName === 'random') {
          const pool = typeof CURSES_DATA !== 'undefined' ? CURSES_DATA : [];
          if (pool.length > 0) curseName = pool[Math.floor(Math.random() * pool.length)].name;
        }
        if (curseName && curseName !== 'random') {
          if (typeof StateMutator !== 'undefined' && StateMutator.addCurse) {
            StateMutator.addCurse(curseName, { notify: false });
          } else if (typeof gameState !== 'undefined' && Array.isArray(gameState.activeCurses)) {
            const pool = typeof CURSES_DATA !== 'undefined' ? CURSES_DATA : [];
            const curseData = pool.find(c => c.name === curseName);
            if (curseData) gameState.activeCurses.push({ ...curseData });
          }
          // Side-effect: "Add X to your Deck" curses add the named card
          const pool2 = typeof CURSES_DATA !== 'undefined' ? CURSES_DATA : [];
          const curseObj = pool2.find(c => c.name === curseName);
          if (curseObj && curseObj.description) {
            const addMatch = curseObj.description.match(/Add (.+?) to your Deck/i);
            if (addMatch) {
              const cardName = addMatch[1].trim();
              if (typeof addCardToDeck === 'function') {
                const cardPool = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA : (typeof cards !== 'undefined' ? cards : []);
                const cardTemplate = cardPool.find(c => c.name === cardName);
                if (cardTemplate) addCardToDeck({ ...cardTemplate });
              }
            }
          }
          if (typeof updateCursesDisplay === 'function') updateCursesDisplay();
          if (typeof createNotification === 'function') createNotification(`Cursed: ${curseName}`, '#e74c3c', '😈');
          lines.push(`Cursed: ${curseName}`);
        }
        break;
      }

      case 'remove_curse': {
        const activeCurses = typeof gameState !== 'undefined' ? gameState.activeCurses : null;
        if (Array.isArray(activeCurses) && activeCurses.length > 0) {
          const idx = effect.value === 'random'
            ? Math.floor(Math.random() * activeCurses.length)
            : activeCurses.findIndex(c => c.name === effect.value);
          if (idx >= 0) {
            const removed = activeCurses.splice(idx, 1)[0];
            if (typeof updateCursesDisplay === 'function') updateCursesDisplay();
            if (typeof createNotification === 'function') createNotification(`Curse lifted: ${removed.name}`, '#2ecc71', '✨');
            lines.push(`Curse removed: ${removed.name}`);
          } else {
            lines.push('No matching curse');
          }
        } else {
          lines.push('No curse to remove');
        }
        break;
      }

      case 'combat_status': {
        if (!gameState.pendingCombatStatuses) gameState.pendingCombatStatuses = [];
        gameState.pendingCombatStatuses.push({ status: effect.status, stacks: effect.stacks || 1 });
        lines.push(`Start next combat with ${effect.stacks || 1}× ${effect.status}`);
        break;
      }

      case 'combat_flag': {
        if (effect.flag === 'ambush') {
          gameState.pendingAmbush = (gameState.pendingAmbush || 0) + 1;
          lines.push('Ambush! Draw 2 extra cards first turn');
        } else if (effect.flag === 'ambushed') {
          gameState.pendingAmbushed = (gameState.pendingAmbushed || 0) + 1;
          lines.push('Ambushed! Draw 2 fewer cards first turn');
        }
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
// SHARED MODAL BUILDER
// ─────────────────────────────────────────────────────────────────────────────

function _eventModal(content) {
  createGameModal(`
    <div style="
      position:relative;
      background:#1a1a2e;
      border-radius:12px;
      max-width:760px;
      width:92vw;
      margin:0 auto;
      overflow:hidden;
    ">
      ${content}
    </div>
  `);
}

// Image strip shown on choice screen
function _imageStrip(eventImageSrc) {
  const playerImg = _getPlayerImage();
  return `
    <div style="
      display:flex;
      gap:0;
      max-height:320px;
      border-bottom:2px solid #333;
      background:#0d0d1a;
    ">
      <div style="
        flex:1;
        display:flex;
        align-items:center;
        justify-content:center;
        min-width:0;
        overflow:hidden;
      ">
        <img src="${eventImageSrc}" alt="" style="
          max-height:320px;
          max-width:100%;
          width:auto;
          height:auto;
          object-fit:contain;
          display:block;
          image-rendering:pixelated;
        " onerror="this.style.display='none'">
      </div>
      ${playerImg ? `<div style="
        width:110px;
        flex-shrink:0;
        background:url('${playerImg}') center top/cover no-repeat;
        border-left:2px solid #333;
        min-height:220px;
      "></div>` : ''}
    </div>
  `;
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 1 — CHOICE LIST
// ─────────────────────────────────────────────────────────────────────────────

function _showChoiceScreen(event, onContinue) {
  const desc = _fillName(event.description);
  const difficulty = _getRollDifficulty();

  const choicesHTML = event.choices.map((choice, i) => {
    const icon = STAT_ICONS[choice.stat] || '🎲';
    const statVal = _getStat(choice.stat);
    const effectiveNeeded = Math.max(1, difficulty - statVal);
    const hint = choice.type === 'stat_check'
      ? `<span style="color:#aaa;font-size:11px;display:block;margin-top:3px;">
           ${icon} ${_statLabel(choice.stat)} check — need ${effectiveNeeded}+ (roll ${difficulty}+ with +${statVal} stat)
         </span>`
      : '';
    return `
      <button class="ev-choice" data-idx="${i}" style="
        width:100%;padding:13px 16px;margin-bottom:9px;
        background:#252535;border:2px solid #444;
        border-left:5px solid ${choice.type === 'stat_check' ? '#e67e22' : '#3498db'};
        border-radius:8px;color:#eee;cursor:pointer;text-align:left;font-size:14px;
        transition:background 0.12s,transform 0.12s;
      "
      onmouseover="this.style.background='#2e2e45';this.style.transform='translateX(4px)'"
      onmouseout="this.style.background='#252535';this.style.transform=''">
        ${choice.text}${hint}
      </button>`;
  }).join('');

  _eventModal(`
    ${_imageStrip(event.image)}
    <div style="padding:22px 26px;">
      <h2 style="color:#c39bd3;margin:0 0 10px;font-size:20px;">❓ ${event.name}</h2>
      <p style="color:#ccc;font-size:14px;line-height:1.6;margin:0 0 18px;">${desc}</p>
      ${choicesHTML}
    </div>
  `);

  document.querySelectorAll('.ev-choice').forEach(btn => {
    btn.addEventListener('click', () => {
      const choice = event.choices[parseInt(btn.dataset.idx)];
      if (choice.type === 'stat_check') {
        _showSuccessRollScreen(event, choice, onContinue);
      } else {
        const lines = applyEventEffects(choice.outcome && choice.outcome.effects ? choice.outcome.effects : []);
        _showOutcomeScreen(choice.outcome || {}, lines, null, onContinue);
      }
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 2 — SUCCESS ROLL
// ─────────────────────────────────────────────────────────────────────────────

function _showSuccessRollScreen(event, choice, onContinue) {
  const difficulty  = _getRollDifficulty();
  const statVal     = _getStat(choice.stat);
  const needed      = Math.max(1, difficulty - statVal);  // what the die itself must show
  const hasAdvantage = _rollsAdvantage();
  const luckVal     = typeof luck !== 'undefined' ? luck : 0;

  const diceHTML = _diceButtonsHTML(hasAdvantage, 'roll-success');

  _eventModal(`
    ${_imageStrip(event.image)}
    <div style="padding:24px 28px;text-align:center;">
      <div style="color:#e67e22;font-size:13px;font-weight:bold;letter-spacing:1px;margin-bottom:6px;">
        SUCCESS CHECK
      </div>
      <div style="color:#fff;font-size:22px;font-weight:bold;margin-bottom:6px;">
        Roll ${needed}+ to succeed
      </div>
      <div style="color:#aaa;font-size:13px;margin-bottom:20px;">
        ${STAT_ICONS[choice.stat]} ${_statLabel(choice.stat)}: +${statVal} bonus
        (need ${difficulty} total, you add +${statVal})
        ${luckVal > 0 ? `&nbsp;·&nbsp; 🍀 Luck ${luckVal} → ${hasAdvantage ? 'Advantage!' : 'No advantage this time'}` : ''}
      </div>
      ${diceHTML}
    </div>
  `);

  document.querySelectorAll('.ev-die-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const result = _rollD20(hasAdvantage);
      const rolled = result.used;
      const success = (rolled + statVal) >= difficulty;

      _showRollAnimation(result.rolls, result.used, success ? '#2ecc71' : '#e74c3c',
        success ? 'SUCCESS' : 'FAILURE',
        `${rolled} + ${statVal} = ${rolled + statVal} vs ${difficulty}`,
        () => _showCritRollScreen(event, choice, success, onContinue)
      );
    }, { once: true });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 3 — CRITICAL ROLL
// ─────────────────────────────────────────────────────────────────────────────

function _showCritRollScreen(event, choice, wasSuccess, onContinue) {
  const CRIT_THRESHOLD = 18;
  const hasAdvantage   = _rollsAdvantage();
  const luckVal        = typeof luck !== 'undefined' ? luck : 0;
  const successColor   = wasSuccess ? '#2ecc71' : '#e74c3c';
  const successLabel   = wasSuccess ? 'SUCCESS' : 'FAILURE';

  const diceHTML = _diceButtonsHTML(hasAdvantage, 'roll-crit');

  _eventModal(`
    ${_imageStrip(event.image)}
    <div style="padding:24px 28px;text-align:center;">
      <div style="
        display:inline-block;
        background:${successColor}22;
        border:1px solid ${successColor};
        border-radius:6px;padding:4px 14px;font-size:13px;
        color:${successColor};font-weight:bold;margin-bottom:14px;
      ">${successLabel}</div>
      <div style="color:#c39bd3;font-size:13px;font-weight:bold;letter-spacing:1px;margin-bottom:6px;">
        CRITICAL CHECK
      </div>
      <div style="color:#fff;font-size:22px;font-weight:bold;margin-bottom:6px;">
        Roll 18+ for a critical outcome (18, 19, or 20)
      </div>
      <div style="color:#aaa;font-size:13px;margin-bottom:20px;">
        No stat bonus applies
        ${luckVal > 0 ? `&nbsp;·&nbsp; 🍀 Luck ${luckVal} → ${hasAdvantage ? 'Advantage!' : 'No advantage this time'}` : ''}
      </div>
      ${diceHTML}
    </div>
  `);

  document.querySelectorAll('.ev-die-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      const result = _rollD20(hasAdvantage);
      const rolled = result.used;
      const isCrit = rolled >= CRIT_THRESHOLD;

      let outcomeKey;
      if (wasSuccess && isCrit)  outcomeKey = 'crit_good';
      else if (wasSuccess)       outcomeKey = 'good';
      else if (isCrit)           outcomeKey = 'crit_bad';
      else                       outcomeKey = 'bad';

      const outcome = (choice.outcomes && choice.outcomes[outcomeKey]) || { description: 'Nothing happens.', effects: [] };

      _showRollAnimation(result.rolls, result.used, isCrit ? '#f1c40f' : '#aaa',
        isCrit ? 'CRITICAL' : 'NOT CRITICAL',
        `Rolled ${rolled} vs 18`,
        () => {
          const effectLines = applyEventEffects(outcome.effects || []);
          _showOutcomeScreen(outcome, effectLines, { outcomeKey, wasSuccess, isCrit }, onContinue);
        }
      );
    }, { once: true });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// ROLL ANIMATION (shared)
// ─────────────────────────────────────────────────────────────────────────────

function _diceButtonsHTML(hasAdvantage, cls) {
  const dieface = `
    <svg viewBox="0 0 40 40" width="60" height="60" fill="none">
      <polygon points="20,2 38,38 2,38" stroke="#c39bd3" stroke-width="2" fill="#1a1a2e"/>
      <text x="20" y="30" text-anchor="middle" fill="#fff" font-size="16" font-weight="bold">?</text>
    </svg>`;
  if (hasAdvantage) {
    return `
      <p style="color:#aaa;font-size:12px;margin-bottom:10px;">🍀 Advantage — click a die to roll both and take the best</p>
      <div style="display:flex;gap:20px;justify-content:center;">
        <button class="ev-die-btn ${cls}" style="${_dieBtnStyle()}">${dieface}</button>
        <button class="ev-die-btn ${cls}" style="${_dieBtnStyle()}">${dieface}</button>
      </div>`;
  }
  return `
    <p style="color:#aaa;font-size:12px;margin-bottom:10px;">Click the die to roll</p>
    <div style="display:flex;justify-content:center;">
      <button class="ev-die-btn ${cls}" style="${_dieBtnStyle()}">${dieface}</button>
    </div>`;
}

function _dieBtnStyle() {
  return `background:none;border:none;cursor:pointer;padding:8px;
    transition:transform 0.15s,filter 0.15s;filter:drop-shadow(0 0 8px #c39bd388);`
    + `onmouseover:this.style.transform='scale(1.15)';onmouseout:this.style.transform='scale(1)'`;
}

function _showRollAnimation(rolls, used, color, label, subtitle, onDone) {
  // Spinning number animation then lock on result
  let frames = 0;
  const SPIN_FRAMES = 18;

  const buildHTML = (displayNums, settled) => `
    <div style="padding:40px 28px;text-align:center;">
      <div style="display:flex;gap:24px;justify-content:center;margin-bottom:20px;">
        ${displayNums.map((n, i) => {
          const isUsed = (n === used) && settled;
          return `<div style="
            font-size:72px;font-weight:bold;
            color:${settled && isUsed ? color : '#fff'};
            text-shadow:0 0 ${settled && isUsed ? '24px ' + color : '12px #ffffff88'};
            transition:color 0.3s,text-shadow 0.3s;
            ${settled && rolls.length > 1 && !isUsed ? 'opacity:0.35;' : ''}
          ">${n}</div>`;
        }).join('')}
      </div>
      ${settled ? `
        <div style="color:${color};font-size:20px;font-weight:bold;margin-bottom:6px;">${label}</div>
        <div style="color:#aaa;font-size:13px;">${subtitle}</div>
      ` : ''}
    </div>`;

  _eventModal(buildHTML(rolls.map(() => '?'), false));

  const tick = () => {
    frames++;
    const randNums = rolls.map(() => Math.floor(Math.random() * 20) + 1);
    _eventModal(buildHTML(randNums, false));
    if (frames < SPIN_FRAMES) {
      setTimeout(tick, 40 + frames * 2);
    } else {
      _eventModal(buildHTML(rolls, true));
      setTimeout(onDone, 1200);
    }
  };
  setTimeout(tick, 60);
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 4 — OUTCOME
// ─────────────────────────────────────────────────────────────────────────────

function _showOutcomeScreen(outcome, effectLines, rollMeta, onContinue) {
  const color = rollMeta ? OUTCOME_COLORS[rollMeta.outcomeKey] : '#aaa';
  const label = rollMeta ? OUTCOME_LABELS[rollMeta.outcomeKey] : '';

  const headerHTML = label ? `
    <div style="
      display:inline-block;
      background:${color}22;border:1px solid ${color};
      border-radius:6px;padding:5px 18px;font-size:14px;
      color:${color};font-weight:bold;margin-bottom:14px;
    ">${label}</div>` : '';

  const effectsHTML = effectLines.length > 0 ? `
    <div style="
      background:#11111f;border-radius:8px;padding:10px 16px;
      margin:14px 0;font-size:13px;color:#ddd;text-align:left;display:inline-block;min-width:180px;
    ">
      ${effectLines.map(l => `<div style="margin-bottom:3px;">• ${l}</div>`).join('')}
    </div>` : '';

  createGameModal(`
    <div style="padding:28px 30px;text-align:center;max-width:560px;margin:0 auto;">
      ${headerHTML}
      <p style="color:#ddd;font-size:15px;line-height:1.65;margin:0 0 10px;">
        ${_fillName(outcome.description || 'Nothing happens.')}
      </p>
      ${effectsHTML}
      <div style="margin-top:22px;">
        <button id="ev-continue-btn" style="
          padding:12px 38px;background:${color || '#555'};
          border:none;border-radius:8px;color:#fff;font-weight:bold;
          font-size:15px;cursor:pointer;
          box-shadow:0 0 18px ${color ? color + '55' : '#0003'};
        ">Continue to Combat</button>
      </div>
    </div>
  `);

  document.getElementById('ev-continue-btn').addEventListener('click', () => {
    closeGameModal();
    if (typeof onContinue === 'function') onContinue();
  }, { once: true });
}

// ─────────────────────────────────────────────────────────────────────────────
// MAIN ENTRY POINT
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Show a random event (or specificEvent by id/name), then call onCombat.
 * @param {string|null} specificEvent
 * @param {Function}    onCombat  - called after the event fully resolves
 */
function showEventModal(specificEvent, onCombat) {
  const allEvents = typeof EVENTS_DATA !== 'undefined' ? EVENTS_DATA : [];
  // New-engine events have an `image` property; old-format events do not
  const pool = allEvents.filter(e => e.image);

  // Default onCombat: start dice or old combat
  const startCombat = typeof onCombat === 'function' ? onCombat : () => {
    if (window.useDiceCombat && typeof showDiceCombatModal === 'function') {
      showDiceCombatModal();
    } else if (typeof showCombatModal === 'function') {
      showCombatModal();
    }
  };

  if (pool.length === 0) {
    console.warn('EVENT-ENGINE: No new-format events in EVENTS_DATA — skipping to combat');
    startCombat();
    return;
  }

  let event;
  if (specificEvent) {
    event = pool.find(e => e.id === specificEvent || e.name === specificEvent);
  }
  if (!event) {
    event = pool[Math.floor(Math.random() * pool.length)];
  }

  if (typeof gameState !== 'undefined') {
    gameState.phase = 'event';
    gameState.currentEvent = event.name;
  }
  if (typeof updateInventory === 'function') updateInventory();

  _showChoiceScreen(event, startCombat);
}

// Expose globally
window.showEventModal    = showEventModal;
window.applyEventEffects = applyEventEffects;
