/**
 * COMBAT-UI.JS - STS-style Card Combat UI (Part 1: Layout + Enemies + Player + Log)
 *
 * Layout:
 *   Top bar      — turn counter, gold, health
 *   Arena        — enemies (center-top) | combat log (right panel)
 *   Player zone  — portrait + HP | powers zone | end-turn button
 *   Hand zone    — fanned card hand (Part 2)
 *   Bottom bar   — draw pile | energy orb | discard | exhaust (Part 2)
 */

console.log('✅ COMBAT-UI.JS (STS Parts 1+2+3+4) loaded');

// ============== CONSTANTS & COLORS ==============

const C = {
  bg:         'linear-gradient(160deg, #160404 0%, #2a0e0e 50%, #160404 100%)',
  panel:      'rgba(10,0,0,0.65)',
  border:     '#5a1a1a',
  gold:       '#c8aa6e',
  goldBright: '#ffd700',
  text:       '#e8d5b0',
  textDim:    '#9a8060',
  hp:         '#c0392b',
  hpBg:       '#3d0d0d',
  block:      '#2980b9',
  blockBg:    '#0a2030',
  green:      '#4CAF50',
  red:        '#e74c3c',
  attack:     '#c0392b',
  skill:      '#2471a3',
  power:      '#8e44ad',
  dice:       '#d68910',
  status:     '#717d7e',
  common:     '#aaaaaa',
  uncommon:   '#4CAF50',
  rare:       '#9b59b6',
  starter:    '#888888',
};

function typeColor(type) {
  return C[(type || '').toLowerCase()] || C.common;
}
function rarityColor(rarity) {
  return C[(rarity || '').toLowerCase()] || C.common;
}

// ============== KEYWORD DICTIONARY ==============
// Any term in a card description that matches a key (case-insensitive) will show
// a definition panel to the right of the card on hover.
const KEYWORD_DEFS = {
  // Mechanics
  'exhaust':          'Permanently removed from your deck for the rest of combat.',
  'retain':           'Not discarded at end of turn.',
  'innate':           'Placed in your hand at the start of combat.',
  'ethereal':         'If still in hand at end of turn, this card is Exhausted.',
  'sly':              'When discarded, triggers its Sly effect.',
  'cleave':           'Hits all enemies and allies.',
  'indiscriminate':   'Hits all enemies.',
  'destroy':          'Permanently removed from your deck (not just this combat).',
  'conjure':          'Adds a card directly to your hand.',
  'melee':            'A close-range physical attack.',
  'ranged':           'A long-range attack.',
  'infuse':           'Gain the specified amount of mana.',
  'unplayable':       'Cannot be played from hand.',
  // Status effects
  'weak':             'Reduces all outgoing damage by 25%.',
  'vulnerable':       'Takes 50% more damage from all hits.',
  'poison':           'Takes N damage at start of each turn. Stacks; each stack decays by 1 per turn.',
  'burn':             'Takes N fire damage at start of each turn. Decays each turn.',
  'thorns':           'Deals N damage back to melee attackers. Also adds N to your own melee attacks.',
  'dodge':            'Negates the next N incoming hits entirely.',
  'frail':            'Takes double damage.',
  'stun':             'Cannot act for 1 turn.',
  'blur':             'Block is preserved at the start of your next turn instead of clearing.',
  'barricade':        'Block does not clear at the start of your turn.',
  'brace':            'Reduces incoming damage by N per stack.',
  'bruise':           'Incoming melee and ranged attacks deal +1 damage per stack.',
  'choked':           'Takes extra damage when targeted.',
  'shackled':         'Cannot gain block.',
  'regeneration':     'Heals N HP at the start of each turn.',
  'power':            'Increases outgoing damage (player) or incoming (enemy) by N stacks.',
  'holy shield':      'Negates the next N hits entirely (before block).',
  'soul link':        'Shares health loss with all other soul-linked entities.',
  'leeches':          'Drains HP from the target on hit.',
  'bleed':            'Deals damage over time.',
  'oiled':            'Increases damage taken from fire.',
  'ritual':           'Gains power stacks at end of each turn.',
  'defense':          'Adds a flat bonus to all block gained.',
  'block':            'Absorbs incoming damage before HP is lost. Clears at start of your turn.',
  'next turn block':  'Gain N block at the start of your next turn.',
  'next turn draw':   'Draw N extra cards at the start of your next turn.',
  'next turn energy': 'Gain N extra energy at the start of your next turn.',
  'well-laid plans':  'Retains up to N cards in hand at end of turn.',
  'shiv':             '0-cost attack card that deals 4 damage. Exhaust.',
  'assassinate':      'Deals double damage if the target is below 50% HP.',
  'fishing weight':   'No additional effect.',
  'wealth':           'Adds +1 damage for every 10 Gold you currently have.',
};

// Extract unique keywords found in a card description
function getCardKeywords(card) {
  const desc = (card.description || '').toLowerCase();
  const found = [];
  for (const [kw, def] of Object.entries(KEYWORD_DEFS)) {
    // Use word-boundary–style check (preceded/followed by non-word or start/end)
    const regex = new RegExp('(?:^|[^a-z])' + kw.replace(/[-]/g, '[- ]') + '(?:$|[^a-z])', 'i');
    if (regex.test(desc)) {
      found.push({ kw: kw.charAt(0).toUpperCase() + kw.slice(1), def });
    }
  }
  return found;
}

// ============== DYNAMIC CARD VALUE HELPERS ==============

/**
 * Compute the actual damage a card would deal, factoring in all player stat modifiers.
 * Mirrors the damage calculation in combat-engine.js playCard().
 * @param {number} baseDmg - Base damage from card description
 * @param {Object} card - Card data
 * @param {Object} combat - Current combat state
 * @param {Object|null} targetEnemy - Enemy being targeted (for Vulnerable/Bruise)
 */
function getCardDynamicDmg(baseDmg, card, combat, targetEnemy) {
  if (!combat || !combat.player) return baseDmg;
  const player = combat.player;
  let dmg = baseDmg;

  // Power bonus (Heavy Blade multiplier if applicable)
  const playerPower = player.statuses['power'] || 0;
  if (playerPower !== 0) {
    const heavyM = (card.description || '').match(/Power affects this card x(\d+) times?/i);
    dmg += playerPower * (heavyM ? parseInt(heavyM[1]) : 1);
  }

  // Combat stat bonuses (Strength/Intelligence/Dexterity/Charisma pigments)
  dmg += (player.statuses['strength']    || 0)
       + (player.statuses['intelligence'] || 0)
       + (player.statuses['dexterity']    || 0)
       + (player.statuses['charisma']     || 0);

  // Scaling counter bonus (Claw, Rampage, etc.)
  if (combat._scalingCounters && combat._scalingCounters[card.name]) {
    dmg += combat._scalingCounters[card.name];
  }

  // Wealth: +1 per 10 gold
  if ((card.description || '').toLowerCase().includes('wealth')) {
    const g = typeof gold !== 'undefined' ? gold
            : (typeof gameState !== 'undefined' ? (gameState.gold || 0) : 0);
    dmg += Math.floor(g / 10);
  }

  // Weak on player: -25%
  if (player.statuses['weak']) dmg = Math.floor(dmg * 0.75);

  // Target Vulnerable: +50% incoming damage
  if (targetEnemy && targetEnemy.statuses && targetEnemy.statuses['vulnerable']) {
    dmg = Math.ceil(dmg * 1.5);
  }

  // Target Bruise: +1 per stack for melee/ranged hits
  if (targetEnemy && targetEnemy.statuses && targetEnemy.statuses['bruise']) {
    dmg += targetEnemy.statuses['bruise'];
  }

  return Math.max(0, dmg);
}

/**
 * Compute actual block a card would give, factoring in Defense status and Frail.
 */
function getCardDynamicBlock(baseBlock, combat) {
  if (!combat || !combat.player) return baseBlock;
  const player = combat.player;
  let block = baseBlock + (player.statuses['defense'] || 0);
  if (player.statuses['frail']) block = Math.floor(block * 0.75);
  return Math.max(0, block);
}

/**
 * Return card description HTML with dynamic numbers substituted where they differ from base.
 * Modified numbers are highlighted: green = buffed, blue = block buffed, red = nerfed.
 * @param {Object} card - Card data
 * @param {Object} combat - Combat state
 * @param {Object|null} targetEnemy - Enemy for Vulnerable/Bruise calculation (null = ignore)
 */
function getCardDisplayDescription(card, combat, targetEnemy) {
  let desc = card.description || '';
  if (!combat || !combat.player) return desc;
  const player = combat.player;

  // Quick check: any modifier active?
  const hasMods = (player.statuses['power'] || 0) !== 0
               || (player.statuses['strength'] || 0) !== 0
               || (player.statuses['intelligence'] || 0) !== 0
               || (player.statuses['dexterity'] || 0) !== 0
               || (player.statuses['charisma'] || 0) !== 0
               || !!player.statuses['weak']
               || !!player.statuses['frail']
               || (player.statuses['defense'] || 0) !== 0
               || !!(combat._scalingCounters && combat._scalingCounters[card.name])
               || desc.toLowerCase().includes('wealth')
               || !!(targetEnemy && targetEnemy.statuses
                    && (targetEnemy.statuses['vulnerable'] || targetEnemy.statuses['bruise']));
  if (!hasMods) return desc;

  // Replace NxM damage (e.g. "Deal 3x2 Dmg")
  desc = desc.replace(/Deal (\d+)[xX](\d+) Dmg/gi, (match, d, t) => {
    const base = parseInt(d), times = parseInt(t);
    const computed = getCardDynamicDmg(base, card, combat, targetEnemy);
    if (computed === base) return match;
    const col = computed > base ? '#7dff7d' : '#ff7d7d';
    return `Deal <span style="color:${col};font-weight:bold">${computed}</span>x${times} Dmg`;
  });

  // Replace plain damage (e.g. "Deal 5 Dmg")
  desc = desc.replace(/Deal (\d+) Dmg/gi, (match, d) => {
    const base = parseInt(d);
    const computed = getCardDynamicDmg(base, card, combat, targetEnemy);
    if (computed === base) return match;
    const col = computed > base ? '#7dff7d' : '#ff7d7d';
    return `Deal <span style="color:${col};font-weight:bold">${computed}</span> Dmg`;
  });

  // Replace block (e.g. "Gain 5 Block" or "Gain +5 Block")
  desc = desc.replace(/Gain \+?(\d+) Block/gi, (match, b) => {
    const base = parseInt(b);
    const computed = getCardDynamicBlock(base, combat);
    if (computed === base) return match;
    const col = computed > base ? '#7dd4ff' : '#ff7d7d';
    return `Gain <span style="color:${col};font-weight:bold">${computed}</span> Block`;
  });

  return desc;
}

// Lightweight re-render of just the hand zone (used when hovered enemy changes)
function refreshCombatHand() {
  const combat = window.CombatEngine && window.CombatEngine.getCombatState();
  const zone = document.getElementById('combat-hand-zone');
  if (!combat || !zone) return;
  const hand = combat.hand || [];
  const n = hand.length;
  zone.innerHTML = n === 0
    ? `<div style="color:${C.textDim};font-size:12px;text-align:center;padding-top:65px;width:100%;">No cards in hand</div>`
    : hand.map((card, i) => renderCardInHand(card, i, n, combat)).join('');
  document.querySelectorAll('.combat-hand-card').forEach(el => {
    el.addEventListener('click', () => handleCardClick(parseInt(el.dataset.handIndex)));
  });
  attachDragMouseDown();
  attachCardTooltip();
}

// Status icon metadata
const STATUS_META = {
  burn:           { img: 'Burn',        emoji: '🔥', label: 'Burn'         },
  poison:         { img: 'Poison',      emoji: '☠',  label: 'Poison'       },
  frail:          { img: 'Frail',       emoji: '💔', label: 'Frail'        },
  vulnerable:     { img: 'Vulnerable',  emoji: '💢', label: 'Vulnerable'   },
  dodge:          { img: 'Dodge',       emoji: '💨', label: 'Dodge'        },
  power:          { img: 'Power',       emoji: '⚡', label: 'Power'        },
  defense:        { img: 'Defense',     emoji: '🛡', label: 'Defense'      },
  ritual:         { img: 'Ritual',      emoji: '🔮', label: 'Ritual'       },
  barricade:      { img: 'Barricade',   emoji: '🏰', label: 'Barricade'    },
  confused:       { img: 'Confused',    emoji: '❓', label: 'Confused'     },
  thorns:         { img: 'Thorns',      emoji: '🌵', label: 'Thorns'       },
  oiled:          { img: 'Oiled',       emoji: '🛢', label: 'Oiled'        },
  multi_attack:   { img: 'MultiAttack', emoji: '⚔', label: 'Multi-Attack'  },
  fading:         { img: 'Fading',      emoji: '⏳', label: 'Fading'       },
  shifting:       { img: 'Shifting',    emoji: '🔄', label: 'Shifting'     },
  formless:       { img: 'Formless',    emoji: '👻', label: 'Formless'     },
  stun:           { img: 'Stun',        emoji: '💫', label: 'Stun'         },
  ruptured:       { img: 'Ruptured',    emoji: '💥', label: 'Ruptured'     },
  weak:           { img: 'Weak',        emoji: '🔻', label: 'Weak'         },
  rerollable:     { img: 'Rerollable',  emoji: '🎲', label: 'Rerollable'   },
  power_per_turn: { img: null,            emoji: '⬆', label: 'Power/Turn'   },
  brace:          { img: 'Brace',         emoji: '🛡', label: 'Brace'        },
  bruise:         { img: 'Bruise',        emoji: '🩹', label: 'Bruise'       },
  forgetful:      { img: 'Forgetful',     emoji: '🌀', label: 'Forgetful'    },
  holy_shield:    { img: 'HolyShield',    emoji: '✨', label: 'Holy Shield'  },
  leeches:        { img: 'Leeches',       emoji: '🩸', label: 'Leeches'      },
  pigment_rich:   { img: 'PigmentRich',   emoji: '🎨', label: 'Pigment Rich' },
  regeneration:   { img: 'Regeneration',  emoji: '💚', label: 'Regeneration' },
  rust:           { img: 'Rust',          emoji: '⚙', label: 'Rust'         },
  soul_link:      { img: 'SoulLink',      emoji: '🔗', label: 'Soul Link'    },
  split:          { img: 'Split',         emoji: '⚡', label: 'Split'        },
  curl_up:        { img: 'CurlUp',        emoji: '🛡', label: 'Curl Up'      },
  // Next-turn statuses (Separate stacking — stored as arrays)
  next_turn_block:  { img: 'NextTurnBlock',   emoji: '🛡', label: 'Next Turn Block'   },
  next_turn_draw:   { img: 'NextTurnDraw',    emoji: '🃏', label: 'Next Turn Draw'    },
  next_turn_energy: { img: 'NextTurnEnergy',  emoji: '⚡', label: 'Next Turn Energy'  },
  // Other statuses
  blur:            { img: 'Blur',           emoji: '🌀', label: 'Blur'            },
  choked:          { img: 'Choked',         emoji: '💀', label: 'Choked'          },
  shackled:        { img: null,             emoji: '🔒', label: 'Shackled'        },
  well_laid_plans: { img: 'Well-LaidPlans', emoji: '📋', label: 'Well-Laid Plans' },
  shiv_per_turn:   { img: null,             emoji: '🗡', label: 'Shiv/Turn'       },
  // Temporary stat boosts (e.g. from pigment cards, "Gain +X Stat until end of combat")
  strength:       { img: null,            emoji: '💪', label: 'Strength'     },
  intelligence:   { img: null,            emoji: '🧠', label: 'Intelligence' },
  dexterity:      { img: null,            emoji: '🏃', label: 'Dexterity'    },
  charisma:       { img: null,            emoji: '✨', label: 'Charisma'     },
};

// ============== MAIN RENDER ENTRY POINT ==============

function renderCombatUI(combat, container) {
  if (!combat || !container) return;

  container.innerHTML = `
    <div id="combat-wrapper" style="
      width: 100%; height: 100%;
      background: ${C.bg};
      display: flex; flex-direction: column;
      font-family: 'Georgia', serif;
      position: relative; overflow: hidden;
      color: ${C.text};
      user-select: none;
    ">
      ${renderItemsBar(combat)}
      ${renderTopBar(combat)}

      <div style="flex:1; display:flex; overflow:hidden; position:relative; min-height:0;">
        <div id="combat-main" style="flex:1; display:flex; flex-direction:column; min-width:0;">
          ${renderEnemiesZone(combat)}
          ${renderPlayerZone(combat)}
        </div>
        ${renderLogPanel(combat)}
      </div>

      ${renderHandZone(combat)}
      ${renderBottomBar(combat)}
    </div>
  `;

  attachCombatEventListeners(combat);
}

// ============== ITEMS BAR ==============

function renderItemsBar(combat) {
  const inv = window.inventory || [];
  if (inv.length === 0) return '';

  const cs = window.CombatEngine ? window.CombatEngine.getCombatState() : null;
  const inc = cs && cs.incrementals;

  const getRarityColor = (rarity) => {
    switch ((rarity || '').toLowerCase()) {
      case 'legendary': return '#ff6b00';
      case 'rare':      return '#9b59b6';
      case 'uncommon':  return '#4CAF50';
      case 'common':    return '#aaa';
      default:          return '#888';
    }
  };

  const getIncrementalCounter = (item) => {
    if ((item.type || '').toLowerCase() !== 'incremental') return '';
    let cur = 0, max = null;
    switch (item.name) {
      case 'Pen Nib':        cur = inc ? inc.attacksTotal % 10 : 0;     max = 10; break;
      case 'Nunchaku':       cur = inc ? inc.attacksTotal % 10 : 0;     max = 10; break;
      case 'Happy Flower':   cur = cs  ? (cs.turn - 1) % 3 : 0;        max = 3;  break;
      case 'Ornamental Fan': cur = inc ? inc.attacksThisTurn % 4 : 0;  max = 4;  break;
      case 'Shuriken':       cur = inc ? inc.attacksThisTurn % 3 : 0;  max = 3;  break;
    }
    if (max === null) return '';
    return `<div style="position:absolute;top:1px;left:1px;background:rgba(0,0,0,0.85);color:#ffcc44;padding:1px 3px;border-radius:3px;font-size:9px;font-weight:bold;border:1px solid #ffcc44;line-height:1.2;">${cur}/${max}</div>`;
  };

  const itemsHTML = inv.map((item, idx) => {
    let imageUrl = (item.image && item.image.trim()) ? item.image : '';
    if (imageUrl.includes('imgur.com/') && !imageUrl.includes('i.imgur.com')) {
      imageUrl = imageUrl.replace('imgur.com/', 'i.imgur.com/');
      if (!imageUrl.match(/\.(png|jpg|jpeg|gif)$/i)) imageUrl += '.png';
    }
    const color = getRarityColor(item.rarity);
    const isUsable = item.type === 'Usable';
    const canUse = isUsable && typeof window.canUseItem === 'function' && window.canUseItem(item);
    const quantityBadge = item.quantity && item.quantity > 1
      ? `<div style="position:absolute;bottom:1px;right:1px;background:rgba(0,0,0,0.9);color:white;padding:1px 3px;border-radius:3px;font-size:9px;font-weight:bold;border:1px solid #ffaa00;">x${item.quantity}</div>`
      : '';
    const imgEl = imageUrl
      ? `<img src="${imageUrl}" alt="${item.name}" style="width:32px;height:32px;object-fit:contain;border-radius:3px;" onerror="this.style.display='none'">`
      : `<div style="width:32px;height:32px;display:flex;align-items:center;justify-content:center;font-size:16px;">?</div>`;
    const useBtn = canUse
      ? `<button onclick="window.useCombatItem(${idx})" style="
          margin-top:2px;padding:1px 5px;font-size:9px;font-weight:bold;
          background:#e67e22;border:none;border-radius:3px;color:white;
          cursor:pointer;white-space:nowrap;line-height:1.4;
         ">Use</button>`
      : '';
    return `
      <div style="
        display:flex;flex-direction:column;align-items:center;gap:1px;
        flex-shrink:0;
      "
         onmouseenter="if(typeof window.showCombatItemTooltip==='function')window.showCombatItemTooltip(event,${idx})"
         onmouseleave="if(typeof window.hideCombatItemTooltip==='function')window.hideCombatItemTooltip()">
        <div style="
          position:relative;width:32px;height:32px;
          border:2px solid ${color};border-radius:4px;
          background:rgba(0,0,0,0.5);
          ${!canUse && isUsable ? 'opacity:0.5;' : ''}
        ">
          ${imgEl}${quantityBadge}${getIncrementalCounter(item)}
        </div>
        ${useBtn}
      </div>
    `;
  }).join('');

  return `
    <div id="combat-items-bar" style="
      background:rgba(0,0,0,0.65);
      border-bottom:1px solid rgba(255,255,255,0.1);
      padding:3px 16px;
      display:flex;align-items:center;gap:8px;
      flex-shrink:0;overflow-x:auto;
    ">
      <span style="color:#aaa;font-size:10px;white-space:nowrap;margin-right:2px;">Items:</span>
      ${itemsHTML}
    </div>
  `;
}

// Called by useCombatItem after an item is used — re-renders the items bar
function updateItemsBar() {
  const itemsBar = document.getElementById('combat-items-bar');
  if (!itemsBar) return;
  const combat = window.CombatEngine && window.CombatEngine.getCombatState();
  if (!combat) return;
  const html = renderItemsBar(combat);
  if (!html) {
    // No items left — remove the bar entirely
    itemsBar.remove();
    return;
  }
  const tmp = document.createElement('div');
  tmp.innerHTML = html;
  const newEl = tmp.firstElementChild;
  if (newEl) itemsBar.replaceWith(newEl);
}

// ============== TOP BAR ==============

function renderTopBar(combat) {
  const p    = combat.player;
  const turn = combat.turn || 1;
  const isPlayerTurn = combat.phase === 'player_action';
  return `
    <div id="combat-topbar" style="
      height: 44px;
      background: rgba(0,0,0,0.7);
      border-bottom: 2px solid ${C.border};
      display: flex; align-items: center;
      justify-content: space-between;
      padding: 0 20px; flex-shrink: 0; z-index: 10;
    ">
      <div style="display:flex; align-items:center; gap:16px;">
        <span style="color:${C.gold}; font-size:15px; font-weight:bold;">Turn ${turn}</span>
        <span style="font-size:13px;">
          ${isPlayerTurn
            ? '<span style="color:#4CAF50;">● Your Turn</span>'
            : '<span style="color:#e74c3c;">● Enemy Turn</span>'}
        </span>
      </div>
      <div style="display:flex; align-items:center; gap:20px; font-size:13px;">
        <span style="color:#e74c3c;">❤ ${p.health}/${p.maxHealth}</span>
        ${p.block > 0 ? `<span style="color:#5dade2;">🛡 ${p.block}</span>` : ''}
        <span style="color:${C.gold};">💰 ${typeof window.gold !== 'undefined' ? window.gold : 0}</span>
      </div>
    </div>
  `;
}

// ============== ENEMIES ZONE ==============

function renderEnemiesZone(combat) {
  const selectedIdx  = combat.selectedCardIndex;
  const selectedCard = (selectedIdx !== null && selectedIdx !== undefined)
    ? (combat.hand || [])[selectedIdx] : null;

  const banner = selectedCard ? `
    <div id="combat-targeting-hint" style="
      position:absolute; top:8px; left:50%; transform:translateX(-50%);
      background:rgba(180,30,30,0.88); border:2px solid #e74c3c;
      color:white; padding:5px 18px; border-radius:20px;
      font-size:12px; font-weight:bold; white-space:nowrap;
      z-index:50; pointer-events:none;
    ">⚔ Select target for "${selectedCard.name}" — Esc to cancel</div>
  ` : '';

  return `
    <div id="combat-enemies-zone" style="
      flex:1; display:flex; position:relative;
      align-items:flex-end; justify-content:center;
      padding:20px 20px 10px; gap:28px;
      min-height:0;
    ">
      ${banner}
      ${combat.enemies.map(e => renderEnemyCard(e, combat)).join('')}
    </div>
  `;
}

function renderEnemyCard(enemy, combat) {
  const isDead       = enemy.health <= 0;
  const isTargeted   = combat.targetedEnemyId === enemy.id;
  const isTargeting  = !isDead && combat.selectedCardIndex !== null
                       && combat.selectedCardIndex !== undefined;
  const hpPct        = Math.max(0, (enemy.health / enemy.maxHealth) * 100);
  const hpColor      = hpPct > 50 ? '#27ae60' : hpPct > 25 ? '#f39c12' : '#c0392b';
  const imgSrc       = enemy.imageUrl || 'images/enemies/default.png';

  const safePattern = (enemy.pattern || '').replace(/"/g, '&quot;');
  return `
    <div id="enemy-card-${enemy.id}"
         class="enemy-card${isTargeting ? ' enemy-targetable' : ''}"
         data-enemy-id="${enemy.id}"
         data-full-pattern="${safePattern}"
         style="
      display: flex; flex-direction: column; align-items: center;
      opacity: ${isDead ? 0.2 : 1};
      transition: opacity 0.4s;
      cursor: ${isDead ? 'default' : 'pointer'};
      min-width: 125px; max-width: 175px;
      position: relative;
    ">
      <!-- Intent badge -->
      <div style="min-height: 32px; margin-bottom: 6px; display:flex; align-items:center;">
        ${isDead ? '<span style="color:#e74c3c;font-size:11px;">Defeated</span>' : renderIntentBadge(enemy)}
      </div>

      <!-- Portrait -->
      <div style="
        width: 120px; height: 120px;
        border-radius: 8px;
        border: 2px solid ${isTargeted ? C.goldBright : isTargeting ? '#c0392b' : C.border};
        background: rgba(0,0,0,0.4);
        display: flex; align-items: center; justify-content: center;
        overflow: hidden;
        box-shadow: ${isTargeted ? `0 0 18px ${C.goldBright}88` : 'none'};
        transition: box-shadow 0.15s, border-color 0.15s;
      ">
        <img src="${imgSrc}" alt="${enemy.name}"
          style="max-width:118px; max-height:118px; object-fit:contain;"
          onerror="this.style.display='none'; this.parentElement.innerHTML='<span style=font-size:56px>👾</span>'">
      </div>

      <!-- Block badge overlay -->
      ${enemy.block > 0 ? `
        <div style="
          position:absolute; top:56px; right:-10px;
          background:${C.block}; color:white;
          border-radius:50%; width:26px; height:26px;
          display:flex; align-items:center; justify-content:center;
          font-size:10px; font-weight:bold;
          border:2px solid #1a1a3a; line-height:1;
        ">🛡${enemy.block}</div>
      ` : ''}

      <!-- Name -->
      <div style="
        margin-top:6px; font-size:12px; font-weight:bold;
        color:${C.text}; text-align:center; line-height:1.2;
      ">${enemy.name}</div>
      <div style="font-size:9px; color:${C.textDim}; margin-bottom:4px;">${enemy.game || ''}</div>

      <!-- HP bar -->
      <div style="
        width:100%; background:${C.hpBg};
        border-radius:4px; height:7px; overflow:hidden;
        border:1px solid rgba(255,255,255,0.1);
      ">
        <div style="
          width:${hpPct}%; height:100%;
          background:${hpColor};
          transition:width 0.3s;
          border-radius:4px;
        "></div>
      </div>
      <div style="font-size:10px; color:${C.text}; margin-top:2px;">
        ${enemy.health} / ${enemy.maxHealth}
      </div>

      <!-- Statuses -->
      <div style="margin-top:4px; min-height:16px;">
        ${renderStatusRow(enemy.statuses, `enemy_${enemy.id}`)}
      </div>
    </div>
  `;
}

// ============== ENEMY PATTERN TOOLTIP ==============

function ensureEnemyPatternTooltip() {
  if (!document.getElementById('enemy-pattern-tooltip')) {
    const tip = document.createElement('div');
    tip.id = 'enemy-pattern-tooltip';
    tip.style.cssText = [
      'position:fixed', 'z-index:9999', 'pointer-events:none',
      'background:#1a1a2e', 'border:1px solid #9b59b6',
      'border-radius:8px', 'padding:8px 12px',
      'font-size:11px', 'color:#e0e0e0', 'line-height:1.7',
      'max-width:280px', 'white-space:pre-wrap',
      'box-shadow:0 4px 16px rgba(0,0,0,0.7)',
      'display:none',
    ].join(';');
    document.body.appendChild(tip);
  }
}

function formatEnemyPattern(pattern) {
  if (!pattern) return 'No pattern data';
  // Ordered: "Turn 1: X | Turn 2: Y | Next: Repeat"
  if (/Turn \d+:/i.test(pattern)) {
    return pattern.split('|').map(s => s.trim()).join('\n');
  }
  // Random: "Always: 75% X / 25% Y"
  const body = pattern.replace(/^Always:\s*/i, '');
  if (body.includes('%') && body.includes('/')) {
    return 'Always:\n' + body.split('/').map(s => '  ' + s.trim()).join('\n');
  }
  return pattern;
}

function showEnemyPatternTooltip(el, e) {
  const tip = document.getElementById('enemy-pattern-tooltip');
  if (!tip) return;
  tip.textContent = formatEnemyPattern(el.dataset.fullPattern || '');
  tip.style.display = 'block';
  positionEnemyPatternTooltip(e);
}

function hideEnemyPatternTooltip() {
  const tip = document.getElementById('enemy-pattern-tooltip');
  if (tip) tip.style.display = 'none';
}

function positionEnemyPatternTooltip(e) {
  const tip = document.getElementById('enemy-pattern-tooltip');
  if (!tip || tip.style.display === 'none') return;
  const x = e.clientX + 14;
  const y = e.clientY - 10;
  tip.style.left = Math.min(x, window.innerWidth - 295) + 'px';
  tip.style.top  = Math.min(y, window.innerHeight - tip.offsetHeight - 10) + 'px';
}

// ============== INTENT BADGE ==============

const INTENT_STYLES = {
  attack:  { bg:'#7b2424', border:'#c0392b', emoji:'⚔', label:'Attack'  },
  defend:  { bg:'#1a3a5c', border:'#2980b9', emoji:'🛡', label:'Defend'  },
  heal:    { bg:'#1a4d2e', border:'#27ae60', emoji:'💚', label:'Heal'    },
  buff:    { bg:'#4a3800', border:'#f39c12', emoji:'⬆', label:'Buff'    },
  debuff:  { bg:'#4d1a4d', border:'#8e44ad', emoji:'💀', label:'Debuff'  },
  spawn:   { bg:'#2c3e50', border:'#7f8c8d', emoji:'➕', label:'Spawn'   },
  unknown: { bg:'#2c2c2c', border:'#7f8c8d', emoji:'❓', label:'Unknown' },
};

function getIntentType(raw) {
  if (!raw) return 'unknown';
  const s = raw.toLowerCase();
  if (s.includes('unknown') || s.includes('charging') || s.includes('wandering')) return 'unknown';
  if (s.includes('dmg') || s.includes('assassinate')) return 'attack';
  if (s.includes('block')) return 'defend';
  if (s.includes('heal'))  return 'heal';
  if (s.includes('ritual') || s.includes('get') || s.includes('power')) return 'buff';
  if (s.includes('inflict') || s.includes('burn') || s.includes('oiled')) return 'debuff';
  if (s.includes('spawn') || s.includes('splitting')) return 'spawn';
  return 'attack';
}

function applyIntentModifiers(rawStr, enemy) {
  const power = (enemy.statuses && enemy.statuses['power']) || 0;
  const weak  = (enemy.statuses && enemy.statuses['weak'])  || 0;
  if (power === 0 && weak === 0) return { text: rawStr, modified: false, modifiers: [] };

  const type = getIntentType(rawStr);
  if (type !== 'attack') return { text: rawStr, modified: false, modifiers: [] };

  const modifiers = [];
  if (power > 0) modifiers.push(`+${power} Power`);
  if (power < 0) modifiers.push(`${power} Power`);
  if (weak  > 0) modifiers.push(`Weak ×0.75`);

  let modified = rawStr;
  let changed = false;

  // Fixed damage: "N Dmg" or "NxM Dmg"
  modified = modified.replace(/(\d+)(x\d+)?\s+[Dd]mg/gi, (match, n, times) => {
    let dmg = parseInt(n);
    if (power !== 0) dmg += power;
    if (weak  >  0) dmg = Math.floor(dmg * 0.75);
    changed = true;
    return `${dmg}${times || ''} Dmg`;
  });

  // Dice damage: "D8 Dmg" → show "+N" suffix for power
  if (power !== 0) {
    modified = modified.replace(/([Dd]\d+(?:[xX]\d+)?(?:\+[Dd]\d+(?:[xX]\d+)?)*)\s+[Dd]mg/gi, (match, dice) => {
      changed = true;
      const sign = power > 0 ? `+${power}` : `${power}`;
      const suffix = weak > 0 ? ` ×0.75` : '';
      return `${dice}${sign}${suffix} Dmg`;
    });
  } else if (weak > 0) {
    // Only weak, dice case
    modified = modified.replace(/([Dd]\d+(?:[xX]\d+)?(?:\+[Dd]\d+(?:[xX]\d+)?)*)\s+[Dd]mg/gi, (match, dice) => {
      changed = true;
      return `${dice} ×0.75 Dmg`;
    });
  }

  return { text: modified, modified: changed, modifiers };
}

function renderIntentBadge(enemy) {
  if (!enemy.currentIntent || enemy.currentIntent.length === 0) return '';

  // If stunned, override display
  if (enemy.statuses && enemy.statuses['stun'] > 0) {
    return `
      <div title="Stunned — skips next turn" style="
        display:inline-flex; align-items:center; gap:4px;
        background:#4a3000; border:1px solid #ff9800;
        border-radius:12px; padding:3px 8px;
        font-size:10px; white-space:nowrap; cursor:default;
        max-width:160px; overflow:hidden;
      ">
        <span style="flex-shrink:0;">💫</span>
        <span style="color:#ff9800; overflow:hidden; text-overflow:ellipsis;">Stunned</span>
      </div>
    `;
  }

  // Get the raw description(s) exactly as written in the pattern column
  const rawStr = enemy.currentIntent.map(i => i.face?.raw || '').filter(Boolean).join(' / ');
  if (!rawStr) return '';

  const type  = getIntentType(rawStr);
  const style = INTENT_STYLES[type] || INTENT_STYLES.unknown;

  // Apply power/weak modifiers to display text
  const { text: displayRaw, modified, modifiers } = applyIntentModifiers(rawStr, enemy);
  const tooltipText = modified
    ? `${rawStr} → ${displayRaw} (${modifiers.join(', ')})`
    : rawStr;

  const displayText = displayRaw.length > 38 ? displayRaw.slice(0, 36) + '…' : displayRaw;

  // Show modifier indicators in badge
  const powerStacks = (enemy.statuses && enemy.statuses['power']) || 0;
  const weakStacks  = (enemy.statuses && enemy.statuses['weak'])  || 0;
  const modBadge = (powerStacks !== 0 || weakStacks > 0) && type === 'attack' ? `
    <span style="
      font-size:9px; background:rgba(0,0,0,0.4);
      border-radius:6px; padding:1px 3px; color:#ffcc44;
    ">${powerStacks !== 0 ? (powerStacks > 0 ? `+${powerStacks}⚡` : `${powerStacks}⚡`) : ''}${weakStacks > 0 ? '↓' : ''}</span>
  ` : '';

  return `
    <div data-intent-tooltip="${tooltipText.replace(/"/g, '&quot;')}" style="
      display:inline-flex; align-items:center; gap:4px;
      background:${style.bg}; border:1px solid ${style.border};
      border-radius:12px; padding:3px 8px;
      font-size:10px; white-space:nowrap; cursor:default;
      max-width:180px; overflow:hidden;
    ">
      <span style="flex-shrink:0;">${style.emoji}</span>
      <span style="color:white; overflow:hidden; text-overflow:ellipsis;">${displayText}</span>
      ${modBadge}
    </div>
  `;
}

// ============== PLAYER ZONE ==============

function renderPlayerZone(combat) {
  const p       = combat.player;
  const charKey = (typeof selectedCharacter !== 'undefined' ? selectedCharacter : null)
                || (typeof gameState !== 'undefined' ? gameState.character : null)
                || 'Rodney';
  const charData = (typeof PLAYER_CHARACTERS !== 'undefined') ? PLAYER_CHARACTERS[charKey] : null;
  const portrait = charData
    ? (charData.fullImage || charData.icon || 'images/characters/Full/Rodney.png')
    : 'images/characters/Full/Rodney.png';
  const hpPct    = Math.max(0, (p.health / p.maxHealth) * 100);
  const hpColor  = hpPct > 50 ? '#27ae60' : hpPct > 25 ? '#f39c12' : '#c0392b';

  const statusRowHTML = renderStatusRow(p.statuses, 'player');
  const hasStatuses   = statusRowHTML.trim().length > 0;

  return `
    <div id="combat-player-zone" style="
      flex-shrink: 0;
      display: flex; flex-direction: column;
      background: rgba(0,0,0,0.35);
      border-top: 2px solid ${C.border};
    ">
      <!-- Main row: portrait | powers | actions -->
      <div style="display:flex; align-items:flex-start; padding:8px 20px; gap:16px;">

        <!-- Portrait + name only -->
        <div style="display:flex; flex-direction:column; align-items:center; width:100px; flex-shrink:0;">
          <div style="
            width:100px; height:120px;
            border-radius:8px; border:2px solid ${C.gold};
            background:rgba(0,0,0,0.5);
            overflow:hidden; display:flex; align-items:flex-end; justify-content:center;
          ">
            <img src="${portrait}" alt="${charKey}"
              style="width:100px; object-fit:cover; object-position:top;"
              onerror="this.style.display='none'; this.parentElement.innerHTML='<span style=font-size:52px>🧙</span>'">
          </div>
          <div style="font-size:11px; color:${C.gold}; margin-top:4px; font-weight:bold;">${charKey}</div>
        </div>

        <!-- Powers zone -->
        <div id="combat-powers-zone" style="
          flex:1; display:flex; flex-wrap:wrap;
          align-content:flex-start; gap:8px; padding:4px;
          min-height:50px;
        ">
          ${renderPowersZone(combat)}
        </div>

        <!-- End turn + energy pips -->
        ${renderActionsZone(combat)}
      </div>

      <!-- Bottom strip: HP bar | block | statuses — full width, never cramped -->
      <div style="
        display:flex; align-items:center; flex-wrap:wrap;
        gap:6px; padding:4px 20px 8px;
        border-top:1px solid rgba(255,255,255,0.08);
      ">
        <!-- HP bar + numbers -->
        <div style="display:flex; align-items:center; gap:6px; flex-shrink:0;">
          <div style="
            width:120px;
            background:${C.hpBg}; border-radius:4px;
            height:10px; overflow:hidden;
            border:1px solid rgba(255,255,255,0.15);
          ">
            <div style="
              width:${hpPct}%; height:100%;
              background:linear-gradient(90deg,${hpColor},${hpColor}cc);
              transition:width 0.3s; border-radius:4px;
            "></div>
          </div>
          <span style="font-size:11px; color:${C.text}; white-space:nowrap;">❤ ${p.health} / ${p.maxHealth}</span>
        </div>

        <!-- Block badge (always visible when > 0) -->
        ${p.block > 0 ? `
          <div style="
            display:flex; align-items:center; gap:4px;
            background:${C.blockBg}; border:1px solid ${C.block};
            border-radius:8px; padding:2px 10px;
            font-size:13px; font-weight:bold; color:#5dade2;
            white-space:nowrap; flex-shrink:0;
          ">🛡 ${p.block}</div>
        ` : ''}

        <!-- Status icons — wrap freely in remaining space -->
        ${hasStatuses ? statusRowHTML : ''}

        <!-- Retained-card badge: shown when cards gained Retain that don't naturally have it -->
        ${(() => {
          const extraRetained = (combat.hand || []).filter(c => c._retain && !/\bretain\b/i.test(c.description || '')).length;
          return extraRetained > 0
            ? `<div style="display:flex;align-items:center;gap:4px;background:rgba(76,175,80,0.18);border:1px solid #4CAF50;border-radius:8px;padding:2px 8px;font-size:11px;color:#4CAF50;white-space:nowrap;flex-shrink:0;">🔒 ${extraRetained} Retained</div>`
            : '';
        })()}
      </div>
    </div>
  `;
}

function renderPowersZone(combat) {
  const count = (combat.powers || []).length;
  const label = count === 0 ? 'Powers' : `Powers (${count})`;
  const active = count > 0;
  return `
    <button onclick="window._showCombatPowers && window._showCombatPowers()" style="
      background:${active ? 'rgba(142,68,173,0.35)' : 'rgba(80,40,100,0.2)'};
      border:1px solid ${active ? '#8e44ad' : '#5a3575'};
      border-radius:8px; padding:5px 14px;
      font-size:12px; color:${active ? '#d7bde2' : '#7a5a8a'};
      cursor:pointer; transition:background 0.15s, border-color 0.15s;
      display:flex; align-items:center; gap:5px;
      align-self:center;
    " onmouseenter="this.style.background='rgba(142,68,173,0.55)'"
      onmouseleave="this.style.background='${active ? 'rgba(142,68,173,0.35)' : 'rgba(80,40,100,0.2)'}'"
    >✨ ${label}</button>
  `;
}

window._showCombatPowers = function() {
  const combat = window.CombatEngine && window.CombatEngine.getCombatState();
  if (!combat) return;
  const powers = combat.powers || [];

  const existing = document.getElementById('combat-powers-overlay');
  if (existing) { existing.remove(); return; }

  const overlay = document.createElement('div');
  overlay.id = 'combat-powers-overlay';
  overlay.style.cssText = `
    position:fixed; inset:0; background:rgba(0,0,0,0.72);
    display:flex; align-items:center; justify-content:center;
    z-index:20000; font-family:'Georgia',serif;
  `;

  const cardsHTML = powers.length === 0
    ? `<div style="color:#888; font-size:14px; padding:20px;">No powers played this combat.</div>`
    : powers.map(card => {
        const bc  = typeColor(card.type);
        const bg  = cardTypeBg(card.type);
        const img = card.imageUrl || '';
        return `
          <div style="
            background:${bg}; border:2px solid ${bc}; border-radius:8px;
            padding:8px; display:flex; flex-direction:column; align-items:center;
            min-width:110px; max-width:130px; flex-shrink:0;
          ">
            <div style="width:100%;height:60px;background:rgba(0,0,0,0.3);border-radius:5px;
              display:flex;align-items:center;justify-content:center;overflow:hidden;margin-bottom:6px;">
              ${img
                ? `<img src="${img}" style="width:100%;height:100%;object-fit:contain;padding:2px;box-sizing:border-box;"
                     onerror="this.style.display='none';this.parentElement.innerHTML='<span style=font-size:28px>✨</span>'">`
                : `<span style="font-size:28px;">✨</span>`}
            </div>
            <div style="font-size:11px;font-weight:bold;color:white;text-align:center;margin-bottom:2px;">
              ${card.name}${card.upgraded ? '<span style="color:#4CAF50">+</span>' : ''}
            </div>
            <div style="font-size:9px;color:#ddd;text-align:center;line-height:1.35;">${card.description}</div>
          </div>
        `;
      }).join('');

  overlay.innerHTML = `
    <div style="
      background:#12001e; border:2px solid #8e44ad; border-radius:12px;
      padding:20px; max-width:680px; width:90vw; max-height:75vh;
      display:flex; flex-direction:column;
      box-shadow:0 10px 40px rgba(0,0,0,0.95);
    ">
      <h2 style="color:#d7bde2; text-align:center; margin:0 0 14px; font-size:17px;">✨ Active Powers</h2>
      <div style="display:flex; gap:10px; flex-wrap:wrap; justify-content:center; overflow-y:auto; flex:1; padding:4px;">
        ${cardsHTML}
      </div>
      <div style="text-align:center; margin-top:14px;">
        <button onclick="document.getElementById('combat-powers-overlay')?.remove()" style="
          padding:8px 24px; background:#444; border:none; border-radius:8px;
          color:#aaa; cursor:pointer; font-size:13px; font-weight:bold;
        ">Close</button>
      </div>
    </div>
  `;
  overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });
  document.body.appendChild(overlay);
};

function renderActionsZone(combat) {
  const isPlayerTurn = combat.phase === 'player_action';
  const energy    = combat.player.energy    || 0;
  const maxEnergy = combat.player.maxEnergy || 3;

  return `
    <div style="
      display:flex; flex-direction:column;
      align-items:center; justify-content:center;
      gap:10px; width:130px; flex-shrink:0;
    ">
      <!-- Energy pips -->
      <div style="display:flex; align-items:center; gap:5px;">
        ${Array.from({length: Math.max(maxEnergy, energy)}, (_, i) => {
          const filled = i < energy;
          const bonus  = i >= maxEnergy; // extra pip from Ice Cream carry-over
          return `<div style="
            width:18px; height:18px; border-radius:50%;
            background:${filled ? (bonus ? '#9b59b6' : '#e67e22') : '#3d2b1a'};
            border:2px solid ${filled ? (bonus ? '#c39bd3' : '#f39c12') : '#5a3a1a'};
            box-shadow:${filled ? (bonus ? '0 0 6px #c39bd3' : '0 0 6px #f39c12') : 'none'};
            transition:all 0.2s;
          "></div>`;
        }).join('')}
        <span style="color:${C.gold}; font-size:12px; margin-left:3px;">${energy}/${maxEnergy}</span>
      </div>

      <!-- End Turn button -->
      <button id="combat-end-turn-btn" style="
        padding:12px 18px;
        background:${isPlayerTurn
          ? 'linear-gradient(145deg,#2e7d32,#1b5e20)'
          : 'linear-gradient(145deg,#3d3d3d,#2a2a2a)'};
        border:3px solid ${isPlayerTurn ? '#4CAF50' : '#555'};
        border-radius:10px; color:white;
        cursor:${isPlayerTurn ? 'pointer' : 'not-allowed'};
        font-weight:bold; font-size:14px;
        width:118px;
        box-shadow:${isPlayerTurn ? '0 0 12px rgba(76,175,80,0.4)' : 'none'};
        transition:all 0.15s; letter-spacing:0.5px;
      " ${!isPlayerTurn ? 'disabled' : ''}>
        ${isPlayerTurn ? 'End Turn' : 'Enemy Turn'}
      </button>

    </div>
  `;
}

// ============== CARD HAND ZONE (Part 2) ==============

function cardTypeBg(type) {
  const bgs = {
    attack: 'rgba(120,30,30,0.92)',
    skill:  'rgba(20,55,100,0.92)',
    power:  'rgba(80,30,120,0.92)',
    dice:   'rgba(100,60,10,0.92)',
    status: 'rgba(50,50,50,0.92)',
  };
  return bgs[(type||'').toLowerCase()] || 'rgba(30,30,30,0.92)';
}

function typeEmoji(type) {
  return {attack:'⚔',skill:'✨',power:'💜',dice:'🎲',status:'⊘'}[(type||'').toLowerCase()] || '🃏';
}

// Check if a card's "If" condition is currently satisfied in combat state.
// Returns true if condition is met (card should glow), false otherwise.
function checkCardCondition(card, combat) {
  const desc = card.description || '';
  const player = combat.player;

  // "If the target has [Status]" — check targeted enemy or any alive enemy
  const targetStatusMatch = desc.match(/If the target has (\w+)/i);
  if (targetStatusMatch) {
    const statusKey = targetStatusMatch[1].toLowerCase();
    // Use targeted enemy, fall back to first alive enemy
    const target = combat.enemies.find(e => e.id === combat.targetedEnemyId && e.health > 0)
                || combat.enemies.find(e => e.health > 0);
    return !!(target && (target.statuses[statusKey] || 0) > 0);
  }

  // "If the target has Poison, deal ... instead" (Bane)
  const baneCondMatch = desc.match(/If the target has (\w+),/i);
  if (baneCondMatch) {
    const statusKey = baneCondMatch[1].toLowerCase();
    const target = combat.enemies.find(e => e.id === combat.targetedEnemyId && e.health > 0)
                || combat.enemies.find(e => e.health > 0);
    return !!(target && (target.statuses[statusKey] || 0) > 0);
  }

  // "If you have Discarded a Card this turn" (Sneaky Strike)
  if (/If you have Discarded a Card this turn/i.test(desc)) {
    return !!combat._discardedThisTurn;
  }

  return false;
}

function renderCardInHand(card, index, total, combat) {
  const isSelected   = combat.selectedCardIndex === index;
  const isPlayerTurn = combat.phase === 'player_action';
  const isXCost      = card.cost === 'X';
  const isNoCost     = card.cost === 'No';
  // Compute effective cost (accounts for Eviscerate / Masterful Stab / free-cost cards)
  const effectiveCost = (window.CombatEngine && window.CombatEngine.getEffectiveCost)
    ? window.CombatEngine.getEffectiveCost(card)
    : (card._freeCost ? 0 : card.cost);
  const displayCost = isXCost ? 'X' : isNoCost ? '—' : effectiveCost;
  const canAfford    = !isNoCost && (isXCost || ((typeof effectiveCost === 'number' ? effectiveCost : card.cost) <= (combat.player.energy || 0)));

  // Check if the card's "If" condition is currently met (highlight like STS)
  const conditionMet = isPlayerTurn && /\bIf\b/i.test(card.description || '') && checkCardCondition(card, combat);

  // Responsive card dimensions based on hand size
  let cardW, cardH, marginL, artH, namePx, descPx, orbW;
  if (total <= 5) {
    cardW = 92; cardH = 134; marginL = -24; artH = 58; namePx = 10; descPx = 8.5; orbW = 27;
  } else if (total <= 7) {
    cardW = 80; cardH = 118; marginL = -18; artH = 50; namePx = 9;  descPx = 7.5; orbW = 25;
  } else if (total <= 9) {
    cardW = 70; cardH = 104; marginL = -14; artH = 44; namePx = 8.5; descPx = 7;  orbW = 23;
  } else {
    cardW = 62; cardH = 92;  marginL = -10; artH = 38; namePx = 8;   descPx = 6.5; orbW = 21;
  }

  // Fan geometry — spread cards in an arc
  const t        = total <= 1 ? 0 : (index - (total - 1) / 2) / ((total - 1) / 2);
  const maxAngle = Math.min(4 * (total - 1), 24);
  const rotation = t * (maxAngle / 2);
  const yLift    = (1 - Math.abs(t)) * 7;

  const borderColor = typeColor(card.type);
  const bgColor     = cardTypeBg(card.type);
  const costColor   = canAfford ? '#ffd700' : '#e74c3c';
  const imgSrc      = card.imageUrl || '';

  const baseTransform = `rotate(${rotation}deg) translateY(${-yLift}px)`;
  const selTransform  = `rotate(${rotation * 0.3}deg) translateY(-30px) scale(1.18)`;
  const hoverTrans    = `rotate(${rotation * 0.2}deg) translateY(-50px) scale(1.42)`;

  // Condition-met glow: bright teal pulse when the "If" clause is satisfied
  const condGlow  = '#00e5ff';
  const boxShadow = isSelected
    ? `0 0 20px ${C.goldBright}bb, 0 0 6px ${borderColor}88`
    : conditionMet
      ? `0 0 14px ${condGlow}cc, 0 0 5px ${condGlow}88, 0 4px 10px rgba(0,0,0,0.6)`
      : `0 4px 10px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.06)`;
  const activeBorder = isSelected ? C.goldBright : conditionMet ? condGlow : borderColor;

  const ml = index > 0 ? `margin-left:${marginL}px;` : '';

  const hoJS  = `this.style.transform='${hoverTrans}';this.style.zIndex='95';this.style.boxShadow='0 10px 30px rgba(0,0,0,0.8), 0 0 16px ${conditionMet ? condGlow : borderColor}99';`;
  const hoOut = `this.style.transform='${isSelected ? selTransform : baseTransform}';this.style.zIndex='${isSelected ? 90 : 20 + index}';this.style.boxShadow='${boxShadow}';`;

  return `
    <div class="combat-hand-card" data-hand-index="${index}"
      style="
        position:relative;
        width:${cardW}px; height:${cardH}px;
        background:${bgColor};
        border:2px solid ${activeBorder};
        border-radius:9px;
        ${ml}
        flex-shrink:0;
        cursor:${isPlayerTurn ? 'pointer' : 'default'};
        opacity:${isPlayerTurn && !canAfford ? 0.55 : 1};
        transform-origin:bottom center;
        transform:${isSelected ? selTransform : baseTransform};
        z-index:${isSelected ? 90 : 20 + index};
        transition:transform 0.14s ease, box-shadow 0.14s ease, opacity 0.1s;
        box-shadow:${boxShadow};
        display:flex; flex-direction:column;
        overflow:hidden;
      "
      onmouseover="${hoJS}"
      onmouseout="${hoOut}"
    >
      <!-- Cost orb -->
      <div style="
        position:absolute; top:-1px; left:-1px;
        width:${orbW}px; height:${orbW}px;
        background:radial-gradient(circle at 38% 32%, #f9cd45, #c07000, #7a3e00);
        border:2px solid ${costColor};
        border-radius:50%;
        display:flex; align-items:center; justify-content:center;
        font-weight:bold; font-size:${orbW - 13}px; color:white;
        z-index:3;
        box-shadow:0 0 7px ${costColor}bb;
        text-shadow:0 1px 2px rgba(0,0,0,0.7);
      ">${isNoCost ? '🚫' : displayCost}</div>

      <!-- Art area -->
      <div style="
        width:100%; height:${artH}px;
        background:linear-gradient(180deg,rgba(0,0,0,0.45),rgba(0,0,0,0.25));
        border-bottom:1px solid ${borderColor}55;
        display:flex; align-items:center; justify-content:center;
        overflow:hidden; flex-shrink:0;
      ">
        ${imgSrc
          ? `<img src="${imgSrc}" alt=""
               style="width:100%;height:100%;object-fit:contain;padding:3px;box-sizing:border-box;"
               onerror="this.style.display='none';this.parentElement.innerHTML='<span style=font-size:${artH - 10}px>${typeEmoji(card.type)}</span>'">`
          : `<span style="font-size:${artH - 10}px;">${typeEmoji(card.type)}</span>`}
      </div>

      <!-- Name -->
      <div style="
        padding:3px 5px 1px;
        font-size:${namePx}px; font-weight:700; color:#f0e8d8;
        text-align:center; line-height:1.2; flex-shrink:0;
        text-shadow:0 1px 3px rgba(0,0,0,0.8);
        letter-spacing:0.2px;
      ">${card.name}${card.upgraded ? `<span style="color:#4CAF50;font-size:${namePx + 1}px;">⁺</span>` : ''}</div>

      <!-- Divider -->
      <div style="height:1px; background:linear-gradient(90deg,transparent,${borderColor}88,transparent); margin:1px 3px; flex-shrink:0;"></div>

      <!-- Description -->
      <div style="
        flex:1; padding:2px 4px;
        font-size:${descPx}px; color:#ccc;
        text-align:center; line-height:1.35;
        overflow:hidden;
      ">${getCardDisplayDescription(card, combat, (() => { const eid = window._combatHoveredEnemyId; return eid && combat.enemies ? combat.enemies.find(e => e.id === eid) || null : null; })())}${card._retain && !/\bretain\b/i.test(card.description) ? ' <span style="color:#4CAF50;font-size:' + (descPx - 0.5) + 'px;">Retain.</span>' : ''}</div>

      <!-- Type footer -->
      <div style="
        padding:2px 4px;
        background:${borderColor}22;
        border-top:1px solid ${borderColor}44;
        font-size:${descPx - 0.5}px; color:${borderColor};
        text-align:center; flex-shrink:0;
        text-transform:uppercase; letter-spacing:0.6px; font-weight:600;
      ">${card.type || 'Card'}</div>

      ${(() => {
        const scalingBonus = combat._scalingCounters && combat._scalingCounters[card.name];
        if (!scalingBonus) return '';
        return `<div style="
          position:absolute; bottom:22px; right:-1px;
          background:#c0392b; border:1px solid #ff6b6b;
          border-radius:6px 0 0 6px;
          padding:1px 5px;
          font-size:${descPx - 0.5}px; font-weight:bold; color:#fff;
          pointer-events:none; z-index:4;
          text-shadow:0 1px 2px rgba(0,0,0,0.7);
        ">+${scalingBonus}</div>`;
      })()}
    </div>
  `;
}

function renderHandZone(combat) {
  const hand    = combat.hand || [];
  const n       = hand.length;

  const cardsHTML = n === 0
    ? `<div style="color:${C.textDim};font-size:12px;text-align:center;padding-top:65px;width:100%;">
         No cards in hand
       </div>`
    : hand.map((card, i) => renderCardInHand(card, i, n, combat)).join('');

  return `
    <div id="combat-hand-zone" style="
      height:178px;
      position:relative;
      flex-shrink:0;
      overflow:visible;
      background:rgba(0,0,0,0.22);
      border-top:1px solid ${C.border};
      display:flex;
      align-items:flex-end;
      justify-content:center;
      padding-bottom:10px;
      padding-left:8px; padding-right:8px;
      z-index:10;
    ">
      ${cardsHTML}
    </div>
  `;
}

// ============== BOTTOM BAR (Part 2) ==============

function renderPileButton(pileType, icon, count, label) {
  const opacity = (pileType === 'exhaust' && count === 0) ? 0.38 : 1;
  return `
    <div onclick="window._showCombatPile('${pileType}')"
      title="${label} (${count} cards)"
      style="
        display:flex; flex-direction:column; align-items:center;
        cursor:pointer; padding:4px 12px;
        background:rgba(255,255,255,0.055);
        border:1px solid ${C.border}; border-radius:8px;
        min-width:54px; opacity:${opacity};
        transition:background 0.1s;
      "
      onmouseover="this.style.background='rgba(255,255,255,0.11)'"
      onmouseout="this.style.background='rgba(255,255,255,0.055)'"
    >
      <div style="font-size:20px; line-height:1;">${icon}</div>
      <div style="font-size:11px; font-weight:bold; color:${C.text};">${count}</div>
      <div style="font-size:8px; color:${C.textDim}; letter-spacing:0.5px;">${label}</div>
    </div>
  `;
}

function renderBottomBar(combat) {
  const draw    = (combat.drawPile    || []).length;
  const discard = (combat.discardPile || []).length;
  const exhaust = (combat.exhaustPile || []).length;
  const energy    = combat.player.energy    || 0;
  const maxEnergy = combat.player.maxEnergy || 3;

  return `
    <div id="combat-bottom-bar" style="
      height:60px;
      background:rgba(0,0,0,0.78);
      border-top:2px solid ${C.border};
      display:flex; align-items:center;
      padding:0 16px; gap:10px;
      flex-shrink:0;
      justify-content:space-between;
      z-index:5;
    ">
      <!-- Draw pile -->
      ${renderPileButton('draw', '📚', draw, 'Draw')}

      <!-- Spacer -->
      <div style="flex:1;"></div>

      <!-- Energy orb (center) -->
      <div style="display:flex; align-items:center; gap:8px;">
        <div style="
          width:48px; height:48px;
          background:radial-gradient(circle at 38% 32%, #ffe27a, #d4820a, #7a3e00);
          border:3px solid ${energy > 0 ? '#f39c12' : '#5a3a20'};
          border-radius:50%;
          display:flex; align-items:center; justify-content:center;
          flex-direction:column;
          box-shadow:${energy > 0 ? '0 0 18px #f39c12bb, 0 0 7px #f39c12' : '0 0 4px #3a2000'};
          transition:box-shadow 0.3s, border-color 0.3s;
          cursor:default;
        ">
          <span style="font-size:17px; font-weight:bold; color:white; line-height:1;">${energy}</span>
          <span style="font-size:8px; color:rgba(255,255,255,0.7); line-height:1;">/${maxEnergy}</span>
        </div>
        <div style="font-size:9px; color:${C.textDim}; line-height:1.5;">
          Energy
        </div>
      </div>

      <!-- Spacer -->
      <div style="flex:1;"></div>

      <!-- Discard + Exhaust -->
      <div style="display:flex; gap:8px;">
        ${renderPileButton('discard', '🗃️', discard, 'Discard')}
        ${renderPileButton('exhaust', '💨',  exhaust, 'Exhaust')}
      </div>
    </div>
  `;
}

// ============== PILE VIEWER MODAL (Part 2) ==============

// Show a pile overlay INSIDE the combat UI (so it doesn't destroy the combat modal)
window._showCombatPile = function(pileType) {
  const combat = window.CombatEngine && window.CombatEngine.getCombatState();
  if (!combat) return;

  const configs = {
    draw:    { pile: combat.drawPile    || [], title: '📚 Draw Pile',    color: '#4CAF50' },
    discard: { pile: combat.discardPile || [], title: '🗃️ Discard Pile', color: '#f39c12' },
    exhaust: { pile: combat.exhaustPile || [], title: '💨 Exhaust Pile', color: '#7f8c8d' },
  };
  const { pile, title, color } = configs[pileType] || configs.draw;

  if (pile.length === 0) {
    typeof createNotification === 'function' &&
      createNotification(`${title} is empty.`, '#888', '📭');
    return;
  }

  // Remove any existing pile overlay
  const existing = document.getElementById('combat-pile-overlay');
  if (existing) existing.remove();

  const cardsHTML = pile.map((card, idx) => {
    const bc  = typeColor(card.type);
    const bg  = cardTypeBg(card.type);
    const img = card.imageUrl || '';
    return `
      <div data-pile-card-idx="${idx}" style="
        background:${bg}; border:2px solid ${bc};
        border-radius:8px; padding:6px 8px;
        display:flex; flex-direction:column; align-items:center;
        min-width:95px; max-width:115px; flex-shrink:0;
        cursor:default; transition:transform 0.12s,box-shadow 0.12s;
      "
      onmouseenter="this.style.transform='scale(1.06)';this.style.boxShadow='0 4px 14px rgba(0,0,0,0.7)'"
      onmouseleave="this.style.transform='';this.style.boxShadow=''">
        <div style="width:100%;height:54px;background:rgba(0,0,0,0.3);border-radius:5px;margin-bottom:5px;
          display:flex;align-items:center;justify-content:center;overflow:hidden;flex-shrink:0;">
          ${img
            ? `<img src="${img}" alt="" style="width:100%;height:100%;object-fit:contain;padding:2px;box-sizing:border-box;"
                 onerror="this.style.display='none';this.parentElement.innerHTML='<span style=font-size:26px>${typeEmoji(card.type)}</span>'">`
            : `<span style="font-size:26px;">${typeEmoji(card.type)}</span>`}
        </div>
        <div style="font-size:10px; font-weight:bold; color:white; text-align:center; margin-bottom:2px;">
          ${card.name}${card.upgraded ? '<span style="color:#4CAF50">+</span>' : ''}
        </div>
        <div style="font-size:9px; color:${bc}; margin-bottom:2px;">${card.type} · ${card.rarity || ''}</div>
        <div style="font-size:8px; color:#ddd; text-align:center; margin-bottom:3px; min-height:20px; line-height:1.3;">${card.description}</div>
        <div style="font-size:10px; color:#ffd700;">⚡${card.cost}</div>
      </div>
    `;
  }).join('');

  const overlay = document.createElement('div');
  overlay.id = 'combat-pile-overlay';
  overlay.style.cssText = `
    position:fixed; inset:0; background:rgba(0,0,0,0.72);
    display:flex; align-items:center; justify-content:center;
    z-index:20000;
  `;
  overlay.innerHTML = `
    <div style="
      background:#1a0808; border:2px solid ${color};
      border-radius:12px; padding:20px;
      max-width:820px; width:90vw; max-height:80vh;
      display:flex; flex-direction:column;
      box-shadow:0 10px 40px rgba(0,0,0,0.9);
      font-family:'Georgia',serif;
    ">
      <h2 style="color:${color}; text-align:center; margin:0 0 14px; font-size:18px;">
        ${title} (${pile.length})
      </h2>
      <div style="
        display:flex; gap:10px; flex-wrap:wrap; justify-content:center;
        overflow-y:auto; flex:1; padding:4px;
      ">
        ${cardsHTML}
      </div>
      <div style="text-align:center; margin-top:14px;">
        <button id="combat-pile-close" style="
          padding:10px 28px; background:#555; border:2px solid #888;
          border-radius:8px; color:white; cursor:pointer;
          font-size:14px; font-weight:bold;
        ">Close</button>
      </div>
    </div>
  `;
  document.body.appendChild(overlay);

  // Close on button click or backdrop click
  document.getElementById('combat-pile-close').addEventListener('click', () => overlay.remove());
  overlay.addEventListener('click', e => { if (e.target === overlay) overlay.remove(); });

  // Click card to zoom in
  overlay.querySelectorAll('[data-pile-card-idx]').forEach(el => {
    el.addEventListener('click', () => {
      const card = pile[parseInt(el.dataset.pileCardIdx)];
      if (card && typeof showCardZoomOverlay === 'function') showCardZoomOverlay(card);
    });
  });
};

// ============== COMBAT LOG PANEL ==============

function renderLogPanel(combat) {
  const logs    = (combat.log || []).slice(-40);
  const logHTML = logs.map(entry => {
    const color = { info:C.textDim, success:'#4CAF50', warning:'#f39c12', danger:'#e74c3c' }[entry.type] || C.text;
    return `<div style="
      padding:2px 8px; font-size:11px; color:${color};
      border-bottom:1px solid rgba(255,255,255,0.04); line-height:1.45;
    ">${entry.message}</div>`;
  }).join('');

  return `
    <div id="combat-log-panel" style="
      width:205px; flex-shrink:0;
      background:rgba(0,0,0,0.55);
      border-left:2px solid ${C.border};
      display:flex; flex-direction:column;
    ">
      <div style="
        padding:6px 10px; font-size:12px; font-weight:bold;
        color:${C.gold}; border-bottom:1px solid ${C.border};
        flex-shrink:0;
      ">📜 Combat Log</div>
      <div id="combat-log-entries" style="
        flex:1; overflow-y:auto;
        display:flex; flex-direction:column-reverse;
        padding:4px 0;
        scrollbar-width:thin;
        scrollbar-color:${C.border} transparent;
      ">
        ${logHTML}
      </div>
    </div>
  `;
}

// ============== STATUS ROW ==============

function showStatusTooltip(event, key, val) {
  let tip = document.getElementById('combat-status-tooltip');
  if (!tip) {
    tip = document.createElement('div');
    tip.id = 'combat-status-tooltip';
    tip.style.cssText = `
      position:fixed; z-index:9000; pointer-events:none;
      background:linear-gradient(145deg,rgba(20,20,30,0.97),rgba(15,15,25,0.97));
      border:2px solid #888; border-radius:8px; padding:10px 12px;
      max-width:240px; box-shadow:0 4px 20px rgba(0,0,0,0.8);
      font-family:'Georgia',serif; font-size:12px; color:#e6d5b8;
    `;
    document.body.appendChild(tip);
  }
  const data = (typeof STATUSES_DATA !== 'undefined') ? STATUSES_DATA[key] : null;
  const meta = STATUS_META[key] || { emoji: '•', label: key };
  const name = data ? data.name : meta.label;
  const desc = data ? data.description : '';
  const type = data ? data.type : '';
  const decay = data ? data.decay : '';
  const typeColor = type === 'Buff' ? '#4CAF50' : type === 'Debuff' ? '#e74c3c' : '#aaa';
  const imgPath = meta.img ? `images/statuses/${meta.img}.png` : null;
  tip.innerHTML = `
    <div style="display:flex;align-items:center;gap:8px;margin-bottom:6px;">
      ${imgPath
        ? `<img src="${imgPath}" style="width:28px;height:28px;object-fit:contain;flex-shrink:0;"
             onerror="this.style.display='none';this.insertAdjacentHTML('afterend','<span style=font-size:18px>${meta.emoji}</span>')">`
        : `<span style="font-size:18px;">${meta.emoji}</span>`}
      <div>
        <div style="font-weight:bold;font-size:13px;">
          ${name}
          ${val > 0 ? `<span style="color:#ffcc44;margin-left:6px;">×${val}</span>` : ''}
        </div>
        ${type ? `<div style="color:${typeColor};font-size:10px;">${type}</div>` : ''}
      </div>
    </div>
    ${desc ? `<div style="color:#ccc;font-size:11px;margin-bottom:4px;line-height:1.4;">${desc}</div>` : ''}
    ${decay && decay !== 'None' ? `<div style="color:#888;font-size:10px;margin-top:2px;">⏱ ${decay}</div>` : ''}
  `;
  const x = Math.min(event.clientX + 12, window.innerWidth - 260);
  const y = Math.min(event.clientY + 12, window.innerHeight - 140);
  tip.style.left = x + 'px';
  tip.style.top  = y + 'px';
  tip.style.display = 'block';
}

function hideStatusTooltip() {
  const tip = document.getElementById('combat-status-tooltip');
  if (tip) tip.style.display = 'none';
}

function renderStatusRow(statuses, _id) {
  if (!statuses) return '';
  // Build entries, expanding array-type Separate statuses into one icon per instance
  const entries = [];
  Object.entries(statuses).forEach(([k, v]) => {
    if (k === 'block') return;
    if (Array.isArray(v)) {
      v.forEach(instance => { if (instance > 0) entries.push([k, instance]); });
    } else if (v > 0) {
      entries.push([k, v]);
    }
  });
  if (!entries.length) return '';
  return `
    <div style="display:flex; flex-wrap:wrap; gap:3px; justify-content:center;">
      ${entries.map(([key, val]) => {
        const meta    = STATUS_META[key] || { img:null, emoji:'•', label:key };
        const imgPath = meta.img ? `images/statuses/${meta.img}.png` : null;
        return `
          <div class="combat-status-icon" style="
            position:relative; width:22px; height:22px;
            display:flex; align-items:center; justify-content:center;
            background:rgba(0,0,0,0.5);
            border:1px solid rgba(255,255,255,0.2);
            border-radius:4px; font-size:10px; cursor:default;
          "
          onmouseenter="if(typeof window.CombatUI!=='undefined'&&window.CombatUI.showStatusTooltip)window.CombatUI.showStatusTooltip(event,'${key}',${val})"
          onmouseleave="if(typeof window.CombatUI!=='undefined'&&window.CombatUI.hideStatusTooltip)window.CombatUI.hideStatusTooltip()">
            ${imgPath
              ? `<img src="${imgPath}" style="width:18px;height:18px;object-fit:contain;"
                   onerror="this.style.display='none';this.insertAdjacentHTML('afterend','<span>${meta.emoji}</span>')">`
              : `<span>${meta.emoji}</span>`}
            ${val > 1 ? `
              <span style="
                position:absolute; bottom:-2px; right:-2px;
                background:rgba(0,0,0,0.85); color:white;
                font-size:9px; font-weight:bold;
                border-radius:3px; padding:0 2px; line-height:1.3;
              ">${val}</span>
            ` : ''}
          </div>
        `;
      }).join('')}
    </div>
  `;
}

// ============== EVENT LISTENERS ==============

function attachCombatEventListeners(combat) {
  // Inject CSS and ensure document-level listeners (idempotent)
  injectCombatInteractionCSS();
  ensureDragAndKeyListeners();

  // End turn button
  const endBtn = document.getElementById('combat-end-turn-btn');
  if (endBtn) {
    endBtn.addEventListener('click', () => {
      if (!window.CombatEngine) return;
      const snap   = captureHPSnapshot(window.CombatEngine.getCombatState());
      const result = window.CombatEngine.endTurn();
      if (result && result.success) {
        const combat = window.CombatEngine.getCombatState();
        showHPDiffs(snap, combat);
        updateCombatDisplay();
        checkCombatEnd();
        // Flush any pending card pick queued by start-of-turn effects (e.g. Tools of the Trade)
        if (combat && combat._pendingCardPick) {
          const pick = combat._pendingCardPick;
          combat._pendingCardPick = null;
          if (typeof window.showCardPickerModal === 'function') {
            window.showCardPickerModal(pick);
          }
        }
      }
    });
  }

  // Enemy clicks + pattern hover tooltip
  // Pattern tooltip shows only when NOT hovering status icons or the intent badge
  ensureEnemyPatternTooltip();
  document.querySelectorAll('.enemy-card').forEach(el => {
    el.addEventListener('click', () => handleEnemyClick(el.dataset.enemyId));
    el.addEventListener('mouseenter', (e) => {
      // Track hovered enemy for dynamic damage preview on hand cards
      window._combatHoveredEnemyId = el.dataset.enemyId;
      refreshCombatHand();
      if (e.target.closest('[data-intent-tooltip]') || e.target.closest('.combat-status-icon')) return;
      showEnemyPatternTooltip(el, e);
    });
    el.addEventListener('mouseleave', () => {
      window._combatHoveredEnemyId = null;
      refreshCombatHand();
      hideEnemyPatternTooltip();
    });
    el.addEventListener('mousemove', (e) => {
      if (e.target.closest('[data-intent-tooltip]') || e.target.closest('.combat-status-icon')) {
        hideEnemyPatternTooltip();
        return;
      }
      positionEnemyPatternTooltip(e);
    });
  });

  // Card hand: click + drag mousedown + tooltip (all per-render)
  document.querySelectorAll('.combat-hand-card').forEach(el => {
    el.addEventListener('click', () => handleCardClick(parseInt(el.dataset.handIndex)));
  });
  attachDragMouseDown();
  attachCardTooltip();
}

function handleEnemyClick(enemyId) {
  const combat = window.CombatEngine && window.CombatEngine.getCombatState();
  if (!combat) return;

  if (combat.selectedCardIndex !== null && combat.selectedCardIndex !== undefined) {
    const cardIndex = combat.selectedCardIndex;
    const snap      = captureHPSnapshot(combat);
    // enemyId already has the full id (e.g. "enemy_0") — pass directly
    const result    = window.CombatEngine.playCard(cardIndex, enemyId);
    if (result && result.success) {
      const hitLog = [...(combat._hitLog || [])];
      combat._hitLog = [];
      combat.selectedCardIndex = null;
      animateCardPlay(cardIndex, enemyId, () => {
        showHPDiffs(snap, combat, hitLog.length > 0);
        checkAndFlashReshuffle(snap, combat);
        replayHits(hitLog, () => {
          updateCombatDisplay();
          checkCombatEnd();
        });
      });
      updateCombatDisplay(); // Immediately remove card from hand
    }
    return;
  }

  combat.targetedEnemyId = enemyId;
  updateCombatDisplay();
}

function handleCardClick(index) {
  const combat = window.CombatEngine && window.CombatEngine.getCombatState();
  if (!combat || combat.phase !== 'player_action') return;

  const hand = combat.hand || [];
  if (index < 0 || index >= hand.length) return;
  const card = hand[index];
  if (!card) return;

  const effectiveCost = (window.CombatEngine && window.CombatEngine.getEffectiveCost)
    ? window.CombatEngine.getEffectiveCost(card)
    : (card._freeCost ? 0 : (card.cost || 0));
  const costIsNo = effectiveCost === 'No' || card.cost === 'No';
  const canAfford = !costIsNo && (card.cost === 'X' || (typeof effectiveCost === 'number' ? effectiveCost : 0) <= (combat.player.energy || 0));
  if (!canAfford) {
    // Shake the card as visual feedback
    const cardEl = document.querySelector(`.combat-hand-card[data-hand-index="${index}"]`);
    if (cardEl) {
      cardEl.classList.add('card-shake');
      setTimeout(() => cardEl.classList.remove('card-shake'), 300);
    }
    typeof createNotification === 'function' &&
      createNotification('Not enough energy!', '#e74c3c', '⚡');
    return;
  }

  const needsTarget = window.CombatEngine.cardNeedsTarget
    ? window.CombatEngine.cardNeedsTarget(card)
    : false;

  if (needsTarget) {
    if (combat.selectedCardIndex === index) {
      combat.selectedCardIndex = null;
    } else {
      combat.selectedCardIndex = index;
    }
    updateCombatDisplay();
  } else {
    const snap   = captureHPSnapshot(combat);
    const result = window.CombatEngine.playCard(index, null);
    if (result && result.success) {
      const hitLog = [...(combat._hitLog || [])];
      combat._hitLog = [];
      combat.selectedCardIndex = null;
      animateCardPlay(index, null, () => {
        showHPDiffs(snap, combat, hitLog.length > 0);
        checkAndFlashReshuffle(snap, combat);
        replayHits(hitLog, () => {
          updateCombatDisplay();
          checkCombatEnd();
        });
      });
      updateCombatDisplay(); // Immediately remove card from hand
    }
  }
}

// ============== PART 3: DRAG-TO-PLAY + TARGETING + TOOLTIP ==============

function injectCombatInteractionCSS() {
  if (document.getElementById('combat-interaction-css')) return;
  const s = document.createElement('style');
  s.id = 'combat-interaction-css';
  s.textContent = `
    @keyframes targetPulse {
      0%,100% { box-shadow: 0 0 0 2px rgba(192,57,43,0.5); }
      50%      { box-shadow: 0 0 0 4px rgba(192,57,43,0.9), 0 0 18px rgba(231,76,60,0.6); }
    }
    .enemy-targetable { animation: targetPulse 1s ease-in-out infinite; cursor: crosshair !important; }
    @keyframes combatShake {
      0%,100% { transform: translateX(0); }
      20%     { transform: translateX(-5px); }
      60%     { transform: translateX(4px); }
      80%     { transform: translateX(-3px); }
    }
    .card-shake { animation: combatShake 0.28s ease-in-out; }
    #combat-drag-clone {
      position: fixed !important;
      pointer-events: none !important;
      z-index: 9998 !important;
      transform: rotate(-6deg) scale(1.1) !important;
      opacity: 0.88 !important;
      transition: none !important;
      margin: 0 !important;
    }
    #combat-card-tooltip { pointer-events:none; transition:opacity 0.08s; }
  `;
  document.head.appendChild(s);
}

// Drag state — persists across re-renders
let _dragState = null;
let _dragListenersAttached = false;

function ensureDragAndKeyListeners() {
  if (_dragListenersAttached) return;
  _dragListenersAttached = true;

  // --- Mouse move: update clone position + highlight enemy under cursor ---
  document.addEventListener('mousemove', e => {
    if (!_dragState) return;
    const dx = e.clientX - _dragState.startX;
    const dy = e.clientY - _dragState.startY;

    if (!_dragState.moved && (Math.abs(dx) > 8 || Math.abs(dy) > 8)) {
      _dragState.moved = true;
      if (_dragState.cardEl) _dragState.cardEl.style.opacity = '0.3';

      // Build clone from live DOM card element
      const rect  = _dragState.cardEl.getBoundingClientRect();
      const clone = _dragState.cardEl.cloneNode(true);
      clone.id    = 'combat-drag-clone';
      clone.removeAttribute('onmouseover');
      clone.removeAttribute('onmouseout');
      clone.style.width  = rect.width  + 'px';
      clone.style.height = rect.height + 'px';
      clone.style.left   = (e.clientX - _dragState.offsetX) + 'px';
      clone.style.top    = (e.clientY - _dragState.offsetY) + 'px';
      document.body.appendChild(clone);
      _dragState.clone = clone;
    }

    if (_dragState.moved && _dragState.clone) {
      _dragState.clone.style.left = (e.clientX - _dragState.offsetX) + 'px';
      _dragState.clone.style.top  = (e.clientY - _dragState.offsetY) + 'px';
    }

    // Highlight enemy under cursor while dragging
    if (_dragState.moved) {
      document.querySelectorAll('.enemy-card').forEach(el => {
        const r    = el.getBoundingClientRect();
        const over = e.clientX >= r.left && e.clientX <= r.right
                  && e.clientY >= r.top  && e.clientY <= r.bottom;
        el.style.outline = over ? `3px solid ${C.goldBright}` : '';
      });
    }
  });

  // --- Mouse up: play card on enemy drop or cancel ---
  document.addEventListener('mouseup', e => {
    if (!_dragState) return;
    const { cardIndex, clone, moved, cardEl } = _dragState;
    _dragState = null;
    if (clone)   clone.remove();
    if (cardEl)  cardEl.style.opacity = '';
    document.querySelectorAll('.enemy-card').forEach(el => el.style.outline = '');

    if (!moved) return; // not a drag — click handler will fire

    const combat = window.CombatEngine && window.CombatEngine.getCombatState();
    if (!combat || combat.phase !== 'player_action') return;

    const card = (combat.hand || [])[cardIndex];
    if (!card) return;

    const canAfford  = card.cost !== 'No' && (card.cost === 'X' || (card.cost || 0) <= (combat.player.energy || 0));
    if (!canAfford) return;

    const needsTarget = window.CombatEngine.cardNeedsTarget
      ? window.CombatEngine.cardNeedsTarget(card) : false;

    if (needsTarget) {
      // Must drop on an enemy
      const enemyEl = document.elementFromPoint(e.clientX, e.clientY)
                        ?.closest('.enemy-card');
      if (enemyEl) {
        combat.selectedCardIndex = cardIndex;
        handleEnemyClick(enemyEl.dataset.enemyId);
      }
      // Dropped elsewhere — cancel silently
    } else {
      // Non-targeted: play on drop anywhere
      const result = window.CombatEngine.playCard(cardIndex, null);
      if (result && result.success) {
        combat.selectedCardIndex = null;
        updateCombatDisplay();
        checkCombatEnd();
      }
    }
  });

  // --- Escape: cancel card selection ---
  document.addEventListener('keydown', e => {
    if (e.key !== 'Escape') return;
    const combat = window.CombatEngine && window.CombatEngine.getCombatState();
    if (combat && combat.selectedCardIndex !== null && combat.selectedCardIndex !== undefined) {
      combat.selectedCardIndex = null;
      updateCombatDisplay();
    }
    if (_dragState) {
      if (_dragState.clone)  _dragState.clone.remove();
      if (_dragState.cardEl) _dragState.cardEl.style.opacity = '';
      _dragState = null;
    }
  });
}

// Per-render: attach mousedown to card elements for drag initiation
function attachDragMouseDown() {
  document.querySelectorAll('.combat-hand-card').forEach(el => {
    el.addEventListener('mousedown', e => {
      if (e.button !== 0) return;
      e.preventDefault(); // prevent text selection during drag
      const rect    = el.getBoundingClientRect();
      _dragState = {
        cardIndex: parseInt(el.dataset.handIndex),
        cardEl:    el,
        clone:     null,
        moved:     false,
        startX:    e.clientX,
        startY:    e.clientY,
        offsetX:   e.clientX - rect.left,
        offsetY:   e.clientY - rect.top,
      };
    });
  });
}

// Card tooltip — persistent div, updated on hover
let _tooltipEl   = null;
let _tooltipTimer = null;

function attachCardTooltip() {
  function getTooltip() {
    if (!_tooltipEl || !document.body.contains(_tooltipEl)) {
      _tooltipEl = document.createElement('div');
      _tooltipEl.id = 'combat-card-tooltip';
      _tooltipEl.style.cssText = 'position:fixed;opacity:0;z-index:200;';
      document.body.appendChild(_tooltipEl);
    }
    return _tooltipEl;
  }

  document.querySelectorAll('.combat-hand-card').forEach(el => {
    el.addEventListener('mouseenter', () => {
      clearTimeout(_tooltipTimer);
      const combat = window.CombatEngine && window.CombatEngine.getCombatState();
      if (!combat) return;
      const idx  = parseInt(el.dataset.handIndex);
      const card = (combat.hand || [])[idx];
      if (!card) return;

      const bc        = typeColor(card.type);
      const bg        = cardTypeBg(card.type);
      const canAfford = card.cost !== 'No' && (card.cost === 'X' || (card.cost || 0) <= (combat.player.energy || 0));
      const costColor = canAfford ? '#ffd700' : '#e74c3c';

      // Find the currently hovered or targeted enemy for damage preview
      const _ttEnemyId = window._combatHoveredEnemyId || combat.targetedEnemyId;
      const _ttEnemy   = _ttEnemyId && combat.enemies
        ? combat.enemies.find(e => e.id === _ttEnemyId && e.health > 0) || null
        : null;

      const tt = getTooltip();

      // Dice cards get a special face-grid tooltip
      const diceResult = (card.type || '').toLowerCase() === 'dice'
        ? renderDiceTooltipContent(card) : null;

      if (diceResult) {
        tt.innerHTML = diceResult.html;
      } else {
        tt.innerHTML = `
          <div style="
            width:168px;
            background:${bg};
            border:2px solid ${bc};
            border-radius:10px; overflow:hidden;
            box-shadow:0 10px 36px rgba(0,0,0,0.9), 0 0 18px ${bc}44;
            font-family:'Georgia',serif;
          ">
            <div style="
              display:flex; align-items:center; gap:8px;
              padding:6px 10px; background:rgba(0,0,0,0.45);
              border-bottom:1px solid ${bc}44;
            ">
              <div style="
                width:30px; height:30px; flex-shrink:0;
                background:radial-gradient(circle at 40% 35%,#f7c03a,#b86000);
                border:2px solid ${costColor}; border-radius:50%;
                display:flex; align-items:center; justify-content:center;
                font-weight:bold; font-size:15px; color:white;
              ">${card.cost === 'No' ? '🚫' : card.cost}</div>
              <div>
                <div style="font-size:12px; font-weight:bold; color:white; line-height:1.2;">
                  ${card.name}${card.upgraded ? '<span style="color:#4CAF50">+</span>' : ''}
                </div>
                <div style="font-size:10px; color:${bc}; text-transform:uppercase; letter-spacing:0.5px;">${card.type}</div>
              </div>
            </div>
            <div style="height:80px; background:rgba(0,0,0,0.35); display:flex; align-items:center; justify-content:center; overflow:hidden;">
              <img src="${card.imageUrl || 'images/cards/default.png'}"
                style="max-width:160px; max-height:78px; object-fit:contain;"
                onerror="this.style.display='none';this.parentElement.innerHTML='<span style=font-size:36px>${typeEmoji(card.type)}</span>'">
            </div>
            <div style="padding:8px 10px; font-size:11px; color:#edd; line-height:1.55; text-align:center; min-height:36px;">
              ${getCardDisplayDescription(card, combat, _ttEnemy)}
            </div>
            ${(() => {
              // Show damage-vs-target preview if the enemy has relevant debuffs
              if (!_ttEnemy) return '';
              const vuln = _ttEnemy.statuses && _ttEnemy.statuses['vulnerable'];
              const bruse = _ttEnemy.statuses && _ttEnemy.statuses['bruise'];
              if (!vuln && !bruse) return '';
              const dmgMatch = (card.description || '').match(/Deal (\d+)(?:[xX](\d+))? Dmg/i);
              if (!dmgMatch) return '';
              const base = parseInt(dmgMatch[1]);
              const baseCalc = getCardDynamicDmg(base, card, combat, null);
              const withTarget = getCardDynamicDmg(base, card, combat, _ttEnemy);
              if (withTarget === baseCalc) return '';
              const tags = [];
              if (vuln) tags.push('💢 Vulnerable');
              if (bruse) tags.push(`🩹 Bruise ×${_ttEnemy.statuses['bruise']}`);
              return `<div style="background:rgba(255,100,0,0.15);border-top:1px solid rgba(255,100,0,0.3);padding:4px 8px;font-size:9px;color:#ffbb77;text-align:center;">
                vs ${_ttEnemy.name}: <strong style="color:#ffdd99;font-size:11px;">${withTarget}</strong> dmg (${tags.join(', ')})
              </div>`;
            })()}
            <div style="
              padding:4px 10px 6px;
              display:flex; justify-content:space-between; align-items:center;
              border-top:1px solid ${bc}33; font-size:9px;
            ">
              <span style="color:${rarityColor(card.rarity)};">${card.rarity || ''}</span>
              <span style="color:${C.textDim};">
                ${card.isStatusCard ? 'Status · Clears' : ''}
                ${card.upgradeEffect && !card.upgraded ? 'Upgradeable' : ''}
              </span>
            </div>
          </div>
        `;
      }

      const rect      = el.getBoundingClientRect();
      const ttW       = diceResult ? diceResult.width : 168;
      const ttH       = diceResult ? (60 + parseDiceFaces(card.description).length * 72) : 260;
      let left = rect.left + rect.width / 2 - ttW / 2;
      let top  = rect.top - ttH - 12;
      if (left < 6)                        left = 6;
      if (left + ttW > window.innerWidth - 6) left = window.innerWidth - ttW - 6;
      if (top  < 6)                        top  = rect.bottom + 8;

      tt.style.left    = left + 'px';
      tt.style.top     = top  + 'px';
      tt.style.opacity = '1';

      // Keyword panel — shown to the right of the card
      const keywords = getCardKeywords(card);
      let kwEl = document.getElementById('combat-card-keywords');
      if (!kwEl) {
        kwEl = document.createElement('div');
        kwEl.id = 'combat-card-keywords';
        kwEl.style.cssText = 'position:fixed;opacity:0;z-index:199;pointer-events:none;transition:opacity 0.12s;';
        document.body.appendChild(kwEl);
      }
      if (keywords.length > 0) {
        kwEl.innerHTML = `<div style="
          background:rgba(10,10,20,0.97); border:1px solid rgba(255,255,255,0.15);
          border-radius:8px; padding:6px 10px; max-width:180px;
          box-shadow:0 6px 24px rgba(0,0,0,0.85);
          display:flex; flex-direction:column; gap:6px;
          font-family:'Georgia',serif;
        ">${keywords.map(({ kw, def }) => `
          <div>
            <div style="font-size:10px; font-weight:bold; color:#f0c070; letter-spacing:0.3px;">${kw}</div>
            <div style="font-size:9px; color:#bbb; line-height:1.4;">${def}</div>
          </div>`).join('<div style="height:1px;background:rgba(255,255,255,0.08);"></div>')}</div>`;
        const kwW  = 192;
        const kwTop = rect.top;
        let   kwLeft = rect.right + 8;
        if (kwLeft + kwW > window.innerWidth - 6) kwLeft = rect.left - kwW - 8;
        kwEl.style.left    = kwLeft + 'px';
        kwEl.style.top     = kwTop  + 'px';
        kwEl.style.opacity = '1';
      } else {
        kwEl.style.opacity = '0';
      }
    });

    el.addEventListener('mouseleave', () => {
      _tooltipTimer = setTimeout(() => {
        if (_tooltipEl) _tooltipEl.style.opacity = '0';
        const kwEl = document.getElementById('combat-card-keywords');
        if (kwEl) kwEl.style.opacity = '0';
      }, 80);
    });
  });
}

// ============== PART 4: ANIMATIONS + 3D DICE ==============

// Unicode die faces (index = face number, 1-based)
const DICE_UNICODE = ['', '⚀', '⚁', '⚂', '⚃', '⚄', '⚅'];

// Snapshot combat HP/block/pile state before an action
function captureHPSnapshot(combat) {
  return {
    playerHP:    combat.player.health,
    playerBlock: combat.player.block || 0,
    drawCount:   (combat.drawPile    || []).length,
    discardCount:(combat.discardPile || []).length,
    enemies: Object.fromEntries(
      (combat.enemies || []).map(e => [e.id, { hp: e.health, block: e.block || 0 }])
    ),
  };
}

// Show floating +/- numbers based on HP diff between snapshot and current state
// skipEnemyDmg: pass true when replayHits will handle per-hit enemy damage numbers
function showHPDiffs(oldSnap, combat, skipEnemyDmg = false) {
  // Player
  const pHP = combat.player.health - oldSnap.playerHP;
  if (pHP < 0) showFloatingNumber('combat-player-zone', Math.abs(pHP), 'damage');
  if (pHP > 0) showFloatingNumber('combat-player-zone', pHP, 'heal');
  const pBlk = (combat.player.block || 0) - oldSnap.playerBlock;
  if (pBlk > 0) showFloatingNumber('combat-player-zone', pBlk, 'block');

  // Enemies — skip individual damage when replayHits will handle it
  if (skipEnemyDmg) return;
  (combat.enemies || []).forEach(e => {
    const prev = oldSnap.enemies[e.id];
    if (!prev) return;
    const hpD  = e.health - prev.hp;
    const blkD = (e.block || 0) - prev.block;
    if (hpD < 0)  showFloatingNumber(`enemy-card-${e.id}`, Math.abs(hpD), 'damage');
    if (hpD > 0)  showFloatingNumber(`enemy-card-${e.id}`, hpD, 'heal');
    if (blkD > 0) showFloatingNumber(`enemy-card-${e.id}`, blkD, 'block');
  });
}

// Flash the draw pile icon when a reshuffle has occurred
function checkAndFlashReshuffle(oldSnap, combat) {
  const newDraw    = (combat.drawPile    || []).length;
  const newDiscard = (combat.discardPile || []).length;
  if (newDraw > oldSnap.drawCount + 2 && newDiscard < oldSnap.discardCount - 2) {
    const btn = document.querySelector("[onclick*=\"_showCombatPile('draw')\"]");
    if (btn) {
      btn.style.transition = 'background 0.12s';
      btn.style.background = 'rgba(76,175,80,0.45)';
      setTimeout(() => { btn.style.background = 'rgba(255,255,255,0.055)'; }, 700);
      showFloatingText('📚 Reshuffled!', '#4CAF50');
    }
  }
}

// Show a brief centered floating text (used for reshuffle etc.)
function showFloatingText(text, color) {
  if (!document.getElementById('combat-float-style')) return; // ensure base CSS exists
  const f = document.createElement('div');
  f.style.cssText = `
    position:fixed; left:50%; top:50%; transform:translate(-50%,-50%);
    color:${color}; font-size:18px; font-weight:bold;
    pointer-events:none; z-index:99999;
    text-shadow:0 1px 6px rgba(0,0,0,0.9);
    animation:floatUp 1.1s ease-out forwards;
  `;
  f.textContent = text;
  document.body.appendChild(f);
  setTimeout(() => f.remove(), 1150);
}

// Animate a card flying from its hand position to a target, then call callback
function animateCardPlay(cardIndex, targetId, callback) {
  const cardEl   = document.querySelector(`.combat-hand-card[data-hand-index="${cardIndex}"]`);
  // targetId is the full enemy id like "enemy_0"; DOM element is "enemy-card-enemy_0"
  const targetEl = targetId ? document.getElementById(`enemy-card-${targetId}`) : null;

  if (!cardEl) { callback(); return; }

  const cRect = cardEl.getBoundingClientRect();
  const tRect = targetEl
    ? targetEl.getBoundingClientRect()
    : { left: window.innerWidth / 2, top: window.innerHeight * 0.3, width: 0, height: 0 };

  const destX = tRect.left + tRect.width  / 2 - cRect.width  / 2;
  const destY = tRect.top  + tRect.height / 2 - cRect.height / 2;

  cardEl.style.opacity = '0.12';

  const clone = cardEl.cloneNode(true);
  clone.removeAttribute('onmouseover');
  clone.removeAttribute('onmouseout');
  clone.style.cssText = `
    position:fixed !important; margin:0 !important;
    pointer-events:none !important; z-index:9997 !important;
    width:${cRect.width}px; height:${cRect.height}px;
    left:${cRect.left}px; top:${cRect.top}px;
    transform-origin:center center;
    transform:rotate(0deg) scale(1); opacity:1;
    transition: left 0.23s cubic-bezier(.4,0,.2,1),
                top  0.23s cubic-bezier(.4,0,.2,1),
                opacity 0.23s, transform 0.23s;
  `;
  document.body.appendChild(clone);

  requestAnimationFrame(() => requestAnimationFrame(() => {
    clone.style.left      = destX + 'px';
    clone.style.top       = destY + 'px';
    clone.style.opacity   = '0';
    clone.style.transform = 'rotate(14deg) scale(0.55)';
  }));

  setTimeout(() => {
    clone.remove();
    callback();
  }, 260);
}

// Parse "1: text\n2: text..." die description into face objects
function parseDiceFaces(description) {
  if (!description) return [];
  return description
    .split(/[\r\n]+/)
    .map(line => line.match(/^(\d+):\s*(.+)$/))
    .filter(Boolean)
    .map(m => ({ num: parseInt(m[1]), text: m[2].trim() }));
}

// Render 3D-style dice card tooltip content
function renderDiceTooltipContent(card) {
  const bc   = typeColor(card.type);
  const desc = card.upgraded && card.upgradedDescription ? card.upgradedDescription : card.description;
  const faces = parseDiceFaces(desc);
  if (!faces.length) return null; // fall through to standard tooltip

  const cols   = faces.length <= 4 ? 2 : 3;
  const width  = cols === 2 ? 200 : 252;

  const facesHTML = faces.map(f => {
    const pip = f.num >= 1 && f.num <= 6 ? DICE_UNICODE[f.num] : `🎲`;
    return `
      <div style="
        background:rgba(255,255,255,0.07);
        border:1px solid rgba(255,255,255,0.18);
        border-radius:8px; padding:5px 4px;
        display:flex; flex-direction:column; align-items:center; gap:2px;
      ">
        <div style="font-size:24px; line-height:1; filter:drop-shadow(0 1px 2px #0008);">
          ${pip}${f.num > 6 ? `<span style="font-size:10px;vertical-align:super;">${f.num}</span>` : ''}
        </div>
        <div style="font-size:8px; color:#e0d0c0; text-align:center; line-height:1.3;">${f.text}</div>
      </div>
    `;
  }).join('');

  const costColor = '#ffd700';
  return {
    width,
    html: `
      <div style="
        width:${width}px;
        background:${cardTypeBg(card.type)};
        border:2px solid ${bc};
        border-radius:10px; overflow:hidden;
        box-shadow:0 10px 36px rgba(0,0,0,0.9), 0 0 18px ${bc}44;
        font-family:'Georgia',serif;
      ">
        <!-- Header -->
        <div style="
          display:flex; align-items:center; gap:8px;
          padding:6px 10px; background:rgba(0,0,0,0.45);
          border-bottom:1px solid ${bc}44;
        ">
          <div style="
            width:28px; height:28px; flex-shrink:0;
            background:radial-gradient(circle at 40% 35%,#f7c03a,#b86000);
            border:2px solid ${costColor}; border-radius:50%;
            display:flex; align-items:center; justify-content:center;
            font-weight:bold; font-size:13px; color:white;
          ">${card.cost}</div>
          <div>
            <div style="font-size:12px; font-weight:bold; color:white;">
              ${card.name}${card.upgraded ? '<span style="color:#4CAF50">+</span>' : ''}
            </div>
            <div style="font-size:9px; color:${bc}; text-transform:uppercase; letter-spacing:0.5px;">
              Dice · ${card.rarity || ''}${card.game ? ' · ' + card.game : ''}
            </div>
          </div>
        </div>
        <!-- Die faces grid -->
        <div style="
          display:grid; grid-template-columns:repeat(${cols},1fr);
          gap:5px; padding:8px;
        ">
          ${facesHTML}
        </div>
        <!-- Footer -->
        <div style="
          padding:3px 10px 5px;
          border-top:1px solid ${bc}33; font-size:9px; color:${C.textDim};
          text-align:center;
        ">Roll on play · ${faces.length}-sided</div>
      </div>
    `,
  };
}

// ============== FLOATING NUMBERS ==============

function showFloatingNumber(elementId, value, type) {
  const el = document.getElementById(elementId);
  if (!el) return;
  const rect = el.getBoundingClientRect();
  const colors = { damage:'#e74c3c', heal:'#4CAF50', block:'#5dade2' };
  const signs  = { damage:'-', heal:'+', block:'🛡+' };

  if (!document.getElementById('combat-float-style')) {
    const s = document.createElement('style');
    s.id = 'combat-float-style';
    s.textContent = `@keyframes floatUp {
      0%   { opacity:1; transform:translateX(-50%) translateY(0);    }
      80%  { opacity:1; transform:translateX(-50%) translateY(-40px);}
      100% { opacity:0; transform:translateX(-50%) translateY(-55px);}
    }`;
    document.head.appendChild(s);
  }

  const f = document.createElement('div');
  f.style.cssText = `
    position:fixed; left:${rect.left + rect.width/2}px; top:${rect.top}px;
    color:${colors[type]||'white'}; font-size:20px; font-weight:bold;
    pointer-events:none; z-index:99999;
    text-shadow:0 1px 4px rgba(0,0,0,0.8);
    transform:translateX(-50%);
    animation:floatUp 1s ease-out forwards;
  `;
  f.textContent = `${signs[type]||''}${value}`;
  document.body.appendChild(f);
  setTimeout(() => f.remove(), 1000);
}

// Show a damage float near a specific combat target
function showTargetedFloat(targetId, dmg) {
  let el;
  if (targetId === 'player') {
    el = document.getElementById('combat-player-zone');
  } else if (targetId) {
    el = document.getElementById(`enemy-card-${targetId}`);
  }
  if (!el) return;
  const rect = el.getBoundingClientRect();
  const f = document.createElement('div');
  f.style.cssText = `
    position:fixed;
    left:${rect.left + rect.width / 2}px;
    top:${rect.top + rect.height * 0.25}px;
    color:#e74c3c; font-size:18px; font-weight:bold;
    pointer-events:none; z-index:99999;
    text-shadow:0 1px 4px rgba(0,0,0,0.9), 0 0 8px rgba(231,76,60,0.5);
    transform:translateX(-50%);
    animation:floatUp 0.75s ease-out forwards;
  `;
  f.textContent = `-${dmg}`;
  document.body.appendChild(f);
  setTimeout(() => f.remove(), 780);
}

// Play back a multi-hit log with 160ms between each hit, then call onDone
function replayHits(hitLog, onDone) {
  const hits = (hitLog || []).filter(h => h && h.dmg > 0);
  if (hits.length <= 1) { onDone && onDone(); return; }
  let i = 0;
  function next() {
    if (i >= hits.length) { onDone && onDone(); return; }
    showTargetedFloat(hits[i].targetId, hits[i].dmg);
    i++;
    setTimeout(next, 160);
  }
  next();
}

// ============== UPDATE / CHECK END ==============

function updateCombatDisplay() {
  const combat    = window.CombatEngine && window.CombatEngine.getCombatState();
  const container = document.getElementById('dice-combat-content');
  if (!combat || !container) return;
  renderCombatUI(combat, container);
  // Keep sidebar Power/Defense in sync with combat statuses
  if (typeof window.updateGameStats === 'function') window.updateGameStats();
}

function checkCombatEnd() {
  // main.js overrides window.CombatUI.checkCombatEnd after combat starts.
  // If it has been replaced, delegate to the override so victory/defeat fires.
  if (window.CombatUI && window.CombatUI.checkCombatEnd !== checkCombatEnd) {
    window.CombatUI.checkCombatEnd();
    return;
  }
  // Fallback: check state directly in case override hasn't been set yet
  const combat = window.CombatEngine && window.CombatEngine.getCombatState();
  if (!combat) return;
  if (combat.phase === 'victory' || combat.phase === 'defeat') {
    console.warn('[CombatUI] checkCombatEnd: phase =', combat.phase, '— no override active');
  }
}

// ============== CARD PICKER MODAL ==============
// Shown when a card effect requires the player to choose card(s) from a pile.
// options: { action: 'discard'|'exhaust', pile: 'hand'|'draw'|'discard'|'exhaust', count: N }

window.showCardPickerModal = function(options) {
  const combat = window.CombatEngine && window.CombatEngine.getCombatState();
  if (!combat) return;

  const { action, pile, count } = options;
  const actionLabel = action === 'discard' ? 'Discard' : action === 'setup' ? 'Setup' : action === 'nightmare' ? 'Choose' : action === 'topdraw' ? 'Top of Draw' : action === 'upgrade' ? 'Upgrade' : action === 'copy' ? 'Copy' : 'Exhaust';
  const actionColor = action === 'discard' ? '#f39c12' : action === 'setup' ? '#4fc3f7' : action === 'nightmare' ? '#9b59b6' : action === 'topdraw' ? '#2ecc71' : action === 'upgrade' ? '#3498db' : action === 'copy' ? '#e67e22' : '#7f8c8d';

  const pileMap = {
    hand:    { cards: combat.hand || [],        label: 'Hand'         },
    draw:    { cards: combat.drawPile || [],    label: 'Draw Pile'    },
    discard: { cards: combat.discardPile || [], label: 'Discard Pile' },
    exhaust: { cards: combat.exhaustPile || [], label: 'Exhaust Pile' },
  };
  let { cards: pileCards, label: pileLabel } = pileMap[pile] || pileMap.hand;

  // Filter by allowed types if specified (Dual Wield — only Attack/Power cards)
  if (options._typesAllowed) {
    pileCards = pileCards.filter(c => options._typesAllowed.includes((c.type || '').toLowerCase()));
  }

  // If nothing to pick from, skip
  if (pileCards.length === 0) return;

  // Track selected indices
  const selected = new Set();

  // Remove any existing picker
  const existing = document.getElementById('combat-card-picker');
  if (existing) existing.remove();

  const overlay = document.createElement('div');
  overlay.id = 'combat-card-picker';
  overlay.style.cssText = `
    position:fixed; inset:0; background:rgba(0,0,0,0.80);
    display:flex; align-items:center; justify-content:center;
    z-index:25000; font-family:'Georgia',serif;
  `;

  overlay.innerHTML = `
    <div id="card-picker-panel" style="
      background:#1a0808; border:2px solid ${actionColor};
      border-radius:12px; padding:20px;
      max-width:840px; width:92vw; max-height:82vh;
      display:flex; flex-direction:column;
      box-shadow:0 10px 40px rgba(0,0,0,0.95);
    ">
      <h2 style="color:${actionColor}; text-align:center; margin:0 0 6px; font-size:18px;">
        ${actionLabel} ${count} Card${count !== 1 ? 's' : ''}
      </h2>
      <p style="color:#aaa; text-align:center; margin:0 0 14px; font-size:12px;">
        ${action === 'nightmare' ? `Choose a card to conjure ${options._nightmareCount || 3} copies of next turn.` : action === 'topdraw' ? `Choose a card to place on top of your Draw Pile.` : action === 'upgrade' ? `Choose a card to upgrade for the rest of combat.` : action === 'copy' ? `Choose an Attack or Power card to conjure ${options._copyCount || 1} cop${(options._copyCount || 1) !== 1 ? 'ies' : 'y'} of to Hand.` : `Choose ${count} card${count !== 1 ? 's' : ''} from your ${pileLabel} to ${actionLabel.toLowerCase()}.`}
      </p>
      <div id="card-picker-grid" style="
        display:flex; gap:10px; flex-wrap:wrap; justify-content:center;
        overflow-y:auto; flex:1; padding:4px;
      ">
        ${pileCards.map((card, idx) => {
          const bc = typeColor(card.type);
          const bg = cardTypeBg(card.type);
          const imgSrc = card.imageUrl || '';
          return `
            <div class="picker-card" data-picker-idx="${idx}" style="
              background:${bg}; border:2px solid ${bc};
              border-radius:8px; padding:6px 8px;
              display:flex; flex-direction:column; align-items:center;
              min-width:95px; max-width:115px; flex-shrink:0;
              cursor:pointer; transition:transform 0.12s, box-shadow 0.12s, border-color 0.12s;
              user-select:none;
            ">
              <div style="width:100%; height:54px; background:rgba(0,0,0,0.35);
                border-radius:5px; margin-bottom:5px;
                display:flex; align-items:center; justify-content:center; overflow:hidden; flex-shrink:0;">
                ${imgSrc
                  ? `<img src="${imgSrc}" alt="" style="width:100%;height:100%;object-fit:contain;padding:2px;box-sizing:border-box;"
                       onerror="this.style.display='none';this.parentElement.innerHTML='<span style=font-size:28px>${typeEmoji(card.type)}</span>'">`
                  : `<span style="font-size:28px;">${typeEmoji(card.type)}</span>`}
              </div>
              <div style="font-size:10px; font-weight:bold; color:white; text-align:center; margin-bottom:2px;">
                ${card.name}${card.upgraded ? '<span style="color:#4CAF50">+</span>' : ''}
              </div>
              <div style="font-size:9px; color:${bc}; margin-bottom:2px;">${card.type} · ${card.rarity || ''}</div>
              <div style="font-size:8px; color:#ddd; text-align:center; margin-bottom:3px; min-height:20px; line-height:1.3;">${card.description}</div>
              <div style="font-size:10px; color:#ffd700;">⚡${card.cost}</div>
            </div>
          `;
        }).join('')}
      </div>
      <div style="display:flex; align-items:center; justify-content:center; gap:14px; margin-top:14px;">
        <span id="picker-selected-count" style="color:#aaa; font-size:13px;">Selected: 0 / ${count}</span>
        <button id="picker-confirm-btn" style="
          padding:10px 28px; background:#555; border:2px solid #888;
          border-radius:8px; color:#888; cursor:not-allowed;
          font-size:14px; font-weight:bold; transition:all 0.15s;
        " disabled>${actionLabel}</button>
      </div>
    </div>
  `;

  document.body.appendChild(overlay);

  const confirmBtn = document.getElementById('picker-confirm-btn');
  const countLabel = document.getElementById('picker-selected-count');

  function updateConfirmBtn() {
    countLabel.textContent = `Selected: ${selected.size} / ${count}`;
    const ready = selected.size === count;
    confirmBtn.disabled = !ready;
    confirmBtn.style.background = ready ? actionColor : '#555';
    confirmBtn.style.borderColor = ready ? actionColor : '#888';
    confirmBtn.style.color       = ready ? '#000' : '#888';
    confirmBtn.style.cursor      = ready ? 'pointer' : 'not-allowed';
  }

  // Card click handler
  overlay.querySelectorAll('.picker-card').forEach(el => {
    el.addEventListener('click', () => {
      const idx = parseInt(el.dataset.pickerIdx);
      if (selected.has(idx)) {
        selected.delete(idx);
        el.style.borderColor = typeColor(pileCards[idx].type);
        el.style.boxShadow = '';
        el.style.transform = '';
      } else {
        if (selected.size >= count) return; // Can't select more
        selected.add(idx);
        el.style.borderColor = actionColor;
        el.style.boxShadow = `0 0 12px ${actionColor}88`;
        el.style.transform = 'scale(1.05)';
      }
      updateConfirmBtn();
    });
  });

  // Confirm handler
  confirmBtn.addEventListener('click', () => {
    if (selected.size !== count) return;

    if (action === 'nightmare') {
      // Nightmare: store chosen card for next-turn conjuring (don't remove from pile)
      const idx = [...selected][0];
      const card = pileCards[idx];
      combat._nightmareCard = { ...card };
      combat._nightmareCount = options._nightmareCount || 3;
      window.CombatEngine && window.CombatEngine.addLog(`Nightmare: will conjure ${combat._nightmareCount}x ${card.name} next turn!`, 'success');
    } else if (action === 'topdraw') {
      // Top of Draw: remove card from source pile, put on top of draw pile
      const idx = [...selected][0];
      const card = pileCards.splice(idx, 1)[0];
      combat.drawPile.unshift(card);
      window.CombatEngine && window.CombatEngine.addLog(`${card.name} → top of Draw Pile`, 'info');
    } else if (action === 'upgrade') {
      // Upgrade: apply upgrade to the selected card in-place (don't move it)
      const idx = [...selected][0];
      const card = pileCards[idx];
      if (!card.upgraded && card.upgradedDescription) {
        card.upgraded = true;
        card.description = card.upgradedDescription;
        if (card.upgradedCost !== null && card.upgradedCost !== undefined) card.cost = card.upgradedCost;
        window.CombatEngine && window.CombatEngine.addLog(`Armaments: upgraded ${card.name}!`, 'success');
      }
    } else if (action === 'copy') {
      // Dual Wield: conjure N copies of the chosen card into hand (don't remove original)
      const idx = [...selected][0];
      const card = pileCards[idx];
      const copyCount = options._copyCount || 1;
      for (let i = 0; i < copyCount; i++) {
        combat.hand.push({ ...card, _uid: `dual_wield_copy_${Date.now()}_${i}` });
      }
      window.CombatEngine && window.CombatEngine.addLog(`Dual Wield: conjured ${copyCount}x ${card.name} to Hand!`, 'success');
    } else {
      // Sort descending so splice doesn't shift indices
      const sortedIdx = [...selected].sort((a, b) => b - a);
      for (const idx of sortedIdx) {
        const card = pileCards.splice(idx, 1)[0];
        if (action === 'discard') {
          combat.discardPile.push(card);
          combat._discardedThisTurn = true;
          combat._discardsThisTurn = (combat._discardsThisTurn || 0) + 1;
          window.CombatEngine && window.CombatEngine.addLog(`Discarded ${card.name}`, 'info');
        } else if (action === 'setup') {
          card._freeCost = true;
          combat.drawPile.unshift(card);
          window.CombatEngine && window.CombatEngine.addLog(`Setup: ${card.name} → top of draw (costs 0)`, 'info');
        } else {
          // Exhaust
          combat.exhaustPile.push(card);
          window.CombatEngine && window.CombatEngine.addLog(`Exhausted ${card.name}`, 'info');
          // Fire on-exhaust triggers (Dark Embrace, etc.)
          if (window.CombatEngine && window.CombatEngine.onCardExhausted) {
            window.CombatEngine.onCardExhausted(card);
          }
        }
      }
    }

    overlay.remove();
    if (typeof renderCombat === 'function') renderCombat();
  });
};

// ============== STUBS ==============

function cleanup3DDice() {}

// ============== EXPORTS ==============

if (typeof window !== 'undefined') {
  window.CombatUI = {
    renderCombatUI,
    updateCombatDisplay,
    checkCombatEnd,
    cleanup3DDice,
    updateItemsBar,
    showFloatingNumber,
    showStatusTooltip,
    hideStatusTooltip,
  };
}
