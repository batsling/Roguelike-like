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

/** Return 'advantage', 'disadvantage', or 'normal' based on luck. */
function _getLuckMode() {
  const lv = typeof luck !== 'undefined' ? luck : 0;
  if (lv > 0 && Math.random() < lv * 0.1)          return 'advantage';
  if (lv < 0 && Math.random() < Math.abs(lv) * 0.1) return 'disadvantage';
  return 'normal';
}

/** Roll a d20 with optional advantage or disadvantage. */
function _rollD20(mode) {
  const a = Math.floor(Math.random() * 20) + 1;
  if (mode === 'normal') return { used: a, rolls: [a] };
  const b = Math.floor(Math.random() * 20) + 1;
  return {
    used: mode === 'advantage' ? Math.max(a, b) : Math.min(a, b),
    rolls: [a, b]
  };
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
  strength: '💪', dexterity: '🤸', intelligence: '🧠', charisma: '💬', constitution: '🫀'
};

function _getConstitution() {
  if (typeof gameState === 'undefined') return 0;
  const base = gameState.startingMaxHealth || gameState.maxHealth || 0;
  const cur  = gameState.maxHealth || 0;
  return Math.floor(Math.max(0, cur - base) / 5);
}

/** Convert an effects array into a short human-readable summary string. */
function _describeEffects(effects) {
  if (!effects || !effects.length) return 'Nothing';
  const parts = effects.map(e => {
    switch (e.type) {
      case 'none':            return null;
      case 'heal':            return `+${e.value} HP`;
      case 'damage':          return `-${e.value} HP`;
      case 'gold':            return (e.value >= 0 ? `+${e.value}` : `${e.value}`) + ' Gold';
      case 'gold_range':      return `+${e.min}–${e.max} Gold`;
      case 'item_tagged':     return `Random ${e.tag} item`;
      case 'curse':           return `Curse: ${e.value}`;
      case 'curse_difficulty': return `Curse: ${e.curseBase} (scaled to difficulty)`;
      case 'combat_status':   return `${e.stacks || 1}× ${e.status}`;
      case 'heal_percent':    return `+${e.value}% Max HP`;
      case 'spawn_enemies': {
        const r = e.min === e.max ? e.min : `${e.min}–${e.max}`;
        return `+${r} ${e.enemy} next fight`;
      }
      case 'combat_flag':
        if (e.flag === 'ambush')   return 'Ambush — draw +2 cards turn 1';
        if (e.flag === 'ambushed') return 'Ambushed — draw −2 cards turn 1';
        return e.flag;
      default:                return null;
    }
  }).filter(Boolean);
  return parts.length ? parts.join(', ') : 'Nothing';
}
function _statLabel(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

function _getConstitutionBonus() { return _getConstitution(); }

function _getStat(statName) {
  if ((statName || '').toLowerCase() === 'constitution') return _getConstitution();
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

      case 'heal_percent': {
        if (typeof health !== 'undefined' && typeof maxHealth !== 'undefined') {
          const amount = Math.round(maxHealth * (effect.value / 100));
          const gain   = Math.min(amount, maxHealth - health);
          if (gain > 0) {
            health = Math.min(maxHealth, health + gain);
            if (typeof gameState !== 'undefined') gameState.health = health;
            if (typeof updateTopBar === 'function') updateTopBar();
          }
          lines.push(`+${gain} HP (${effect.value}% of max)`);
        }
        break;
      }

      case 'spawn_enemies': {
        if (!gameState.pendingSpawnEnemies) gameState.pendingSpawnEnemies = [];
        gameState.pendingSpawnEnemies.push({ enemy: effect.enemy, min: effect.min, max: effect.max });
        const range = effect.min === effect.max ? effect.min : `${effect.min}–${effect.max}`;
        lines.push(`Next fight: +${range} ${effect.enemy}`);
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
        // Use ITEMS_DATA directly — it's the static source guaranteed to have tags.
        // Fall back to the runtime `items` array if ITEMS_DATA isn't present.
        const _src = typeof ITEMS_DATA !== 'undefined' ? ITEMS_DATA
                   : (typeof items !== 'undefined' ? items : []);
        const pool = _src.filter(i =>
          i.rarity && i.rarity !== 'N/A' &&
          Array.isArray(i.tags) && i.tags.some(t => t.toLowerCase() === tag)
        );
        if (pool.length > 0) {
          const item = pool[Math.floor(Math.random() * pool.length)];
          if (typeof acquireItem === 'function') acquireItem(item);
          lines.push(`Item: ${item.name}`);
        } else {
          lines.push(`No "${tag}" item found`);
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

  // Build the outcomes preview panel (hidden by default)
  const ORDER = ['crit_good', 'good', 'bad', 'crit_bad'];
  const outcomesHTML = event.choices.map((choice, i) => {
    const icon = STAT_ICONS[choice.stat] || '🎲';
    const rows = ORDER.map(key => {
      const outcome = choice.outcomes && choice.outcomes[key];
      if (!outcome) return '';
      const color  = OUTCOME_COLORS[key];
      const label  = OUTCOME_LABELS[key];
      const fx     = _describeEffects(outcome.effects);
      const desc   = _fillName(outcome.description || '');
      return `
        <div style="display:flex;gap:10px;align-items:baseline;padding:5px 0;border-bottom:1px solid #2a2a3a;">
          <span style="color:${color};font-size:11px;font-weight:bold;min-width:110px;flex-shrink:0;">${label}</span>
          <span style="color:#bbb;font-size:12px;flex:1;line-height:1.4;">${desc}</span>
          <span style="color:${color};font-size:11px;white-space:nowrap;flex-shrink:0;">${fx}</span>
        </div>`;
    }).join('');
    return `
      <div style="margin-bottom:14px;">
        <div style="color:#e67e22;font-size:12px;font-weight:bold;margin-bottom:6px;padding-bottom:4px;border-bottom:1px solid #444;">
          ${icon} ${choice.text}
        </div>
        ${rows}
      </div>`;
  }).join('');

  const con = _getConstitution();
  const conBar = con > 0
    ? `<div style="color:#7ec8e3;font-size:11px;margin-bottom:12px;">🫀 Constitution ${con} — +${con} to constitution rolls</div>`
    : '';

  _eventModal(`
    ${_imageStrip(event.image)}
    <div style="padding:22px 26px;">
      <h2 style="color:#c39bd3;margin:0 0 10px;font-size:20px;">❓ ${event.name}</h2>
      <p style="color:#ccc;font-size:14px;line-height:1.6;margin:0 0 10px;">${desc}</p>
      ${conBar}
      ${choicesHTML}
      <div style="text-align:right;margin-top:4px;">
        <button id="ev-outcomes-toggle" style="
          background:none;border:1px solid #555;border-radius:6px;
          color:#aaa;font-size:12px;padding:5px 12px;cursor:pointer;
          transition:color 0.15s,border-color 0.15s;
        "
        onmouseover="this.style.color='#eee';this.style.borderColor='#888'"
        onmouseout="this.style.color='#aaa';this.style.borderColor='#555'">
          👁 Show Outcomes
        </button>
      </div>
      <div id="ev-outcomes-panel" style="
        display:none;margin-top:14px;padding:14px 16px;
        background:#13131f;border:1px solid #333;border-radius:8px;
      ">
        ${outcomesHTML}
      </div>
    </div>
  `);

  document.getElementById('ev-outcomes-toggle').addEventListener('click', function() {
    const panel = document.getElementById('ev-outcomes-panel');
    const open  = panel.style.display === 'none';
    panel.style.display  = open ? 'block' : 'none';
    this.textContent     = open ? '👁 Hide Outcomes' : '👁 Show Outcomes';
    this.style.color     = open ? '#c39bd3' : '#aaa';
    this.style.borderColor = open ? '#c39bd3' : '#555';
  });

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
// 3D DICE HELPERS (shared by roll screens)
// ─────────────────────────────────────────────────────────────────────────────

let _activeEventRenderers = [];

function _disposeEventRenderers() {
  _activeEventRenderers.forEach(r => { try { r.dispose(); } catch (_) {} });
  _activeEventRenderers = [];
}

function _makeD20EventData() {
  if (typeof createD20 === 'function') return createD20();
  const sides = [];
  for (let i = 1; i <= 20; i++) {
    sides.push({ value: i, texture: null, modifiers: [], displayValue: null });
  }
  return { type: 'd20', sides, globalModifiers: [], currentRoll: null };
}

/**
 * Initialise one DiceRendererInstance per container id, all D20.
 * Returns array of { renderer, data } objects in the same order as ids.
 * Disposes any previously active event renderers first.
 */
function _initEventDice(containerIds) {
  _disposeEventRenderers();
  const d20Data = _makeD20EventData();
  const instances = [];
  containerIds.forEach(id => {
    const el = document.getElementById(id);
    if (!el || el.clientWidth === 0) return;
    const r = new window.DiceRendererInstance();
    r.init(el, 0x0d0d1a);  // match event modal background
    r.createDice(d20Data);
    instances.push({ renderer: r, data: d20Data, id });
  });
  _activeEventRenderers = instances.map(x => x.renderer);
  return instances;
}

/** HTML for a die container slot. */
function _dieSlotHTML(id, size) {
  return `<div id="${id}" style="
    width:${size}px; height:${size}px; cursor:pointer;
    border-radius:10px; overflow:hidden;
    border:2px solid #3a3a5a;
    transition:border-color 0.3s;
  "></div>`;
}

/** Highlight the used die and dim the discarded one. */
function _highlightWinner(instances, rolls, mode) {
  if (instances.length < 2) return;
  const used  = mode === 'disadvantage' ? Math.min(...rolls) : Math.max(...rolls);
  const color = mode === 'disadvantage' ? '#e74c3c' : '#f1c40f';
  instances.forEach(({ id }, i) => {
    const el = document.getElementById(id);
    if (!el) return;
    if (rolls[i] === used) {
      el.style.borderColor = color;
      el.style.boxShadow   = `0 0 14px ${color}88`;
    } else {
      el.style.opacity     = '0.45';
      el.style.borderColor = '#333';
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 2 — SUCCESS ROLL
// ─────────────────────────────────────────────────────────────────────────────

function _showSuccessRollScreen(event, choice, onContinue) {
  const difficulty = _getRollDifficulty();
  const statVal    = _getStat(choice.stat);
  const needed     = Math.max(1, difficulty - statVal);
  const luckMode   = _getLuckMode();
  const luckVal    = typeof luck !== 'undefined' ? luck : 0;
  const diceCount  = luckMode !== 'normal' ? 2 : 1;
  const diceSize   = diceCount === 2 ? 175 : 210;

  const luckHint = luckMode === 'advantage'
    ? `&nbsp;·&nbsp; 🍀 Luck ${luckVal} → <span style="color:#f1c40f">Advantage!</span>`
    : luckMode === 'disadvantage'
      ? `&nbsp;·&nbsp; 🌑 Luck ${luckVal} → <span style="color:#e74c3c">Disadvantage!</span>`
      : (luckVal !== 0 ? `&nbsp;·&nbsp; Luck ${luckVal} → No effect this roll` : '');

  const dieSlots = Array.from({ length: diceCount }, (_, i) =>
    _dieSlotHTML(`ev-die-s-${i}`, diceSize)
  ).join('');

  const promptText = luckMode === 'advantage'
    ? '🍀 Click a die to roll both — best of two'
    : luckMode === 'disadvantage'
      ? '🌑 Click a die to roll both — worst of two'
      : 'Click the die to roll';

  _eventModal(`
    ${_imageStrip(event.image)}
    <div style="padding:22px 26px;text-align:center;">
      <div style="color:#e67e22;font-size:12px;font-weight:bold;letter-spacing:1.5px;margin-bottom:5px;">
        SUCCESS CHECK
      </div>
      <div style="color:#fff;font-size:20px;font-weight:bold;margin-bottom:5px;">
        Roll ${needed}+ to succeed
      </div>
      <div style="color:#aaa;font-size:12px;margin-bottom:18px;">
        ${STAT_ICONS[choice.stat] || '🎲'} ${_statLabel(choice.stat)}: +${statVal} bonus
        &nbsp;·&nbsp; need ${difficulty} total
        ${luckHint}
      </div>

      <div id="ev-dice-area-s" style="
        display:flex; gap:18px; justify-content:center; margin-bottom:14px;
      ">${dieSlots}</div>

      <p id="ev-prompt-s" style="color:#aaa;font-size:12px;margin:0 0 6px;">${promptText}</p>
      <div id="ev-result-s" style="display:none;margin-top:10px;"></div>
    </div>
  `);

  const ids       = Array.from({ length: diceCount }, (_, i) => `ev-die-s-${i}`);
  const instances = _initEventDice(ids);
  let   rolled    = false;

  const doRoll = () => {
    if (rolled) return;
    rolled = true;
    const prompt = document.getElementById('ev-prompt-s');
    if (prompt) prompt.textContent = 'Rolling…';

    const performRoll = () => {
      const result = _rollD20(luckMode);
      let done = 0;

      instances.forEach(({ renderer, data }, i) => {
        const face = result.rolls[i] !== undefined ? result.rolls[i] : result.rolls[0];
        renderer.rollDice(data, face, () => {
          if (++done < instances.length) return;

          if (luckMode !== 'normal') _highlightWinner(instances, result.rolls, luckMode);

          const success = (result.used + statVal) >= difficulty;
          const color   = success ? '#2ecc71' : '#e74c3c';
          const label   = success ? 'SUCCESS' : 'FAILURE';

          if (prompt) prompt.style.display = 'none';
          const resultDiv = document.getElementById('ev-result-s');
          if (resultDiv) {
            resultDiv.style.display = 'block';
            resultDiv.innerHTML = `
              <div style="color:${color};font-size:26px;font-weight:bold;
                text-shadow:0 0 18px ${color}88;margin-bottom:4px;">${label}</div>
              <div style="color:#bbb;font-size:13px;">
                Rolled ${result.used} + ${statVal} = ${result.used + statVal} vs ${difficulty}
              </div>
              <div id="ev-roll-btns-s" style="margin-top:14px;display:flex;gap:10px;justify-content:center;"></div>`;

            const btnsDiv = document.getElementById('ev-roll-btns-s');
            if (btnsDiv) {
              const rerolls = typeof gameState !== 'undefined' ? (gameState.reroll || 0) : 0;

              const continueBtn = document.createElement('button');
              continueBtn.textContent = 'Continue →';
              continueBtn.style.cssText = `padding:8px 20px;background:#2a5c2a;border:1px solid #4a9c4a;
                color:#fff;border-radius:6px;font-size:14px;cursor:pointer;`;
              continueBtn.onclick = () => {
                _disposeEventRenderers();
                _showCritRollScreen(event, choice, success, onContinue);
              };
              btnsDiv.appendChild(continueBtn);

              if (rerolls > 0) {
                const rerollBtn = document.createElement('button');
                rerollBtn.textContent = `🔄 Reroll (${rerolls} left)`;
                rerollBtn.style.cssText = `padding:8px 20px;background:#5c3a0a;border:1px solid #c07820;
                  color:#f0c850;border-radius:6px;font-size:14px;cursor:pointer;`;
                rerollBtn.onclick = () => {
                  if (typeof gameState !== 'undefined') gameState.reroll = Math.max(0, (gameState.reroll || 0) - 1);
                  resultDiv.style.display = 'none';
                  if (prompt) { prompt.textContent = 'Rolling…'; prompt.style.display = ''; }
                  performRoll();
                };
                btnsDiv.insertBefore(rerollBtn, continueBtn);
              }
            }
          }
        });
      });
    };

    performRoll();
  };

  ids.forEach(id => {
    const el = document.getElementById(id);
    if (el) el.addEventListener('click', doRoll, { once: true });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN 3 — CRITICAL ROLL
// ─────────────────────────────────────────────────────────────────────────────

function _showCritRollScreen(event, choice, wasSuccess, onContinue) {
  const CRIT_THRESHOLD = 18;
  const luckMode       = _getLuckMode();
  const luckVal        = typeof luck !== 'undefined' ? luck : 0;
  const successColor   = wasSuccess ? '#2ecc71' : '#e74c3c';
  const successLabel   = wasSuccess ? 'SUCCESS' : 'FAILURE';
  const diceCount      = luckMode !== 'normal' ? 2 : 1;
  const diceSize       = diceCount === 2 ? 175 : 210;

  const luckHint = luckMode === 'advantage'
    ? `&nbsp;·&nbsp; 🍀 Luck ${luckVal} → <span style="color:#f1c40f">Advantage!</span>`
    : luckMode === 'disadvantage'
      ? `&nbsp;·&nbsp; 🌑 Luck ${luckVal} → <span style="color:#e74c3c">Disadvantage!</span>`
      : (luckVal !== 0 ? `&nbsp;·&nbsp; Luck ${luckVal} → No effect this roll` : '');

  const promptText = luckMode === 'advantage'
    ? '🍀 Click a die to roll both — best of two'
    : luckMode === 'disadvantage'
      ? '🌑 Click a die to roll both — worst of two'
      : 'Click the die to roll';

  const dieSlots = Array.from({ length: diceCount }, (_, i) =>
    _dieSlotHTML(`ev-die-c-${i}`, diceSize)
  ).join('');

  _eventModal(`
    ${_imageStrip(event.image)}
    <div style="padding:22px 26px;text-align:center;">
      <div style="
        display:inline-block;margin-bottom:12px;
        background:${successColor}22;border:1px solid ${successColor};
        border-radius:6px;padding:3px 14px;font-size:12px;
        color:${successColor};font-weight:bold;
      ">${successLabel}</div>

      <div style="color:#c39bd3;font-size:12px;font-weight:bold;letter-spacing:1.5px;margin-bottom:5px;">
        CRITICAL CHECK
      </div>
      <div style="color:#fff;font-size:20px;font-weight:bold;margin-bottom:5px;">
        Roll 18+ for a critical outcome
      </div>
      <div style="color:#aaa;font-size:12px;margin-bottom:18px;">
        No stat bonus — need 18, 19, or 20
        ${luckHint}
      </div>

      <div id="ev-dice-area-c" style="
        display:flex; gap:18px; justify-content:center; margin-bottom:14px;
      ">${dieSlots}</div>

      <p id="ev-prompt-c" style="color:#aaa;font-size:12px;margin:0 0 6px;">${promptText}</p>
      <div id="ev-result-c" style="display:none;margin-top:10px;"></div>
    </div>
  `);

  const ids       = Array.from({ length: diceCount }, (_, i) => `ev-die-c-${i}`);
  const instances = _initEventDice(ids);
  let   rolled    = false;

  const doRoll = () => {
    if (rolled) return;
    rolled = true;
    const prompt = document.getElementById('ev-prompt-c');
    if (prompt) prompt.textContent = 'Rolling…';

    const performRoll = () => {
      const result = _rollD20(luckMode);
      let done = 0;

      instances.forEach(({ renderer, data }, i) => {
        const face = result.rolls[i] !== undefined ? result.rolls[i] : result.rolls[0];
        renderer.rollDice(data, face, () => {
          if (++done < instances.length) return;

          if (luckMode !== 'normal') _highlightWinner(instances, result.rolls, luckMode);

          const isCrit = result.used >= CRIT_THRESHOLD;
          const color  = isCrit ? '#f1c40f' : '#aaa';
          const label  = isCrit ? '⚡ CRITICAL' : 'NOT CRITICAL';

          let outcomeKey;
          if (wasSuccess && isCrit)  outcomeKey = 'crit_good';
          else if (wasSuccess)       outcomeKey = 'good';
          else if (isCrit)           outcomeKey = 'crit_bad';
          else                       outcomeKey = 'bad';

          const outcome = (choice.outcomes && choice.outcomes[outcomeKey])
            || { description: 'Nothing happens.', effects: [] };

          if (prompt) prompt.style.display = 'none';
          const resultDiv = document.getElementById('ev-result-c');
          if (resultDiv) {
            resultDiv.style.display = 'block';
            resultDiv.innerHTML = `
              <div style="color:${color};font-size:26px;font-weight:bold;
                text-shadow:0 0 18px ${color}88;margin-bottom:4px;">${label}</div>
              <div style="color:#bbb;font-size:13px;">Rolled ${result.used} vs 18</div>
              <div id="ev-roll-btns-c" style="margin-top:14px;display:flex;gap:10px;justify-content:center;"></div>`;

            const btnsDiv = document.getElementById('ev-roll-btns-c');
            if (btnsDiv) {
              const rerolls = typeof gameState !== 'undefined' ? (gameState.reroll || 0) : 0;

              const continueBtn = document.createElement('button');
              continueBtn.textContent = 'Continue →';
              continueBtn.style.cssText = `padding:8px 20px;background:#2a5c2a;border:1px solid #4a9c4a;
                color:#fff;border-radius:6px;font-size:14px;cursor:pointer;`;
              continueBtn.onclick = () => {
                _disposeEventRenderers();
                const effectLines = applyEventEffects(outcome.effects || []);
                _showOutcomeScreen(outcome, effectLines, { outcomeKey, wasSuccess, isCrit }, onContinue);
              };
              btnsDiv.appendChild(continueBtn);

              if (rerolls > 0) {
                const rerollBtn = document.createElement('button');
                rerollBtn.textContent = `🔄 Reroll (${rerolls} left)`;
                rerollBtn.style.cssText = `padding:8px 20px;background:#5c3a0a;border:1px solid #c07820;
                  color:#f0c850;border-radius:6px;font-size:14px;cursor:pointer;`;
                rerollBtn.onclick = () => {
                  if (typeof gameState !== 'undefined') gameState.reroll = Math.max(0, (gameState.reroll || 0) - 1);
                  resultDiv.style.display = 'none';
                  if (prompt) { prompt.textContent = 'Rolling…'; prompt.style.display = ''; }
                  performRoll();
                };
                btnsDiv.insertBefore(rerollBtn, continueBtn);
              }
            }
          }
        });
      });
    };

    performRoll();
  };

  ids.forEach(id => {
    const el = document.getElementById(id);
    if (el) el.addEventListener('click', doRoll, { once: true });
  });
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
