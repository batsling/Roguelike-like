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
  'buffer':           'Prevents the next N times the target would lose Health (triggers after block).',
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

/**
 * Return the best image URL for a card.
 * Hero-tagged S&D dice cards use images/heroes/<FirstWord>.png.
 * Falls back to card.imageUrl or empty string.
 */
function getCardImageUrl(card) {
  if (!card) return '';
  const tags = Array.isArray(card.tags) ? card.tags : [];
  if (tags.includes('hero') && (card.game || '').trim() === 'Slice & Dice') {
    const firstName = (card.name || '').split(' ')[0];
    if (firstName) return `images/heroes/${firstName}.png`;
  }
  return card.imageUrl || '';
}
window.getCardImageUrl = getCardImageUrl;

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

  // Double Damage on player: x2
  if (player.statuses['double_damage']) dmg = dmg * 2;

  // Target Vulnerable: +50% incoming damage
  if (targetEnemy && targetEnemy.statuses && targetEnemy.statuses['vulnerable']) {
    dmg = Math.ceil(dmg * 1.5);
  }

  // Target Bruise: +1 per stack for melee/ranged hits
  if (targetEnemy && targetEnemy.statuses && targetEnemy.statuses['bruise']) {
    dmg += targetEnemy.statuses['bruise'];
  }

  // Little Knife: +25% to attacks targeting enemies with lower HP than the player
  if (targetEnemy && (card.type || '').toLowerCase() === 'attack') {
    const _inv = typeof inventory !== 'undefined' ? inventory : [];
    const hasLittleKnife = _inv.some(i => i.name === 'Little Knife');
    if (hasLittleKnife && targetEnemy.health < (combat.player.health || 0)) {
      dmg = Math.ceil(dmg * 1.25);
    }
  }

  // Focus Crystal: +1 flat bonus to melee attacks
  if (/melee/i.test(card.description || '') && combat._flatAttackBonus) {
    dmg += combat._flatAttackBonus;
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
 * Compute actual magic damage a spell would deal, factoring in Arcane and Weak.
 */
function getCardDynamicMagicDmg(baseDmg, card, combat) {
  if (!combat || !combat.player) return baseDmg;
  const player = combat.player;
  const isPowerCard = (card.type || '').toLowerCase() === 'power';
  let dmg = baseDmg + (isPowerCard ? 0 : (player.statuses['arcane'] || 0));
  if (player.statuses['weak']) dmg = Math.floor(dmg * 0.75);
  return Math.max(0, dmg);
}

/**
 * Returns bonus-effect HTML lines granted to a card by inventory items.
 * Shown as small text appended to the card description.
 */
function getCardItemSuffixes(card) {
  const inv = (typeof window.inventory !== 'undefined' ? window.inventory : []);

  const isStrike = (card.name || '').toLowerCase() === 'strike';

  const parts = [];

  if (card._retain)
    parts.push(`<span style="color:#7dff7d">Retain</span>`);

  if (inv && inv.length) {
    if (isStrike && inv.some(i => i.name === 'Leeching Seed'))
      parts.push(`<span style="color:#7dff7d">Heal 1</span>`);

    if (isStrike) {
      const sdCount = inv.filter(i => i.name === 'Strike Dummy').reduce((n, i) => n + (i.quantity || 1), 0);
      if (sdCount > 0) parts.push(`<span style="color:#7dff7d">+${sdCount * 3} Dmg</span>`);
    }

    if (isStrike && inv.some(i => i.name === 'Bird Head'))
      parts.push(`<span style="color:#c39bd3">Soul Link</span>`);

    if (isStrike && inv.some(i => i.name === 'Brass Knuckles'))
      parts.push(`<span style="color:#a569bd">Bruise</span>`);

    if (isStrike) {
      const jarCount = inv.filter(i => i.name === 'Jar of Leeches').length;
      if (jarCount > 0) {
        const cs = window.CombatEngine && window.CombatEngine.getCombatState && window.CombatEngine.getCombatState();
        const persistence = cs && cs.player ? (cs.player.statuses['persistence'] || 0) : 0;
        const leechAmt = (1 + persistence) * jarCount;
        parts.push(`<span style="color:#82e0aa">${leechAmt} Leeches</span>`);
      }
    }
  }

  if (!parts.length) return '';
  return `<br><span style="font-size:0.85em;opacity:0.9">${parts.join(' · ')}</span>`;
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

  const itemSuffix = getCardItemSuffixes(card);

  // Duplicator: weapon attack cards show +1 hit count in description
  const _dupInv = typeof inventory !== 'undefined' ? inventory : [];
  const hasDuplicator = card.type && card.type.toLowerCase() === 'attack' &&
                        card.tags && card.tags.includes('weapon') &&
                        _dupInv.some(i => i.name === 'Duplicator');

  const persistence = player.statuses['persistence'] || 0;

  // Little Knife: active when targeting an enemy with lower HP than player, for attack cards
  const hasLittleKnife = (card.type || '').toLowerCase() === 'attack' &&
                         _dupInv.some(i => i.name === 'Little Knife') &&
                         !!(targetEnemy && targetEnemy.health < (player.health || 0));

  // Quick check: any modifier active?
  const hasMods = itemSuffix.length > 0
               || hasDuplicator
               || hasLittleKnife
               || (player.statuses['power'] || 0) !== 0
               || (player.statuses['arcane'] || 0) !== 0
               || (player.statuses['strength'] || 0) !== 0
               || (player.statuses['intelligence'] || 0) !== 0
               || (player.statuses['dexterity'] || 0) !== 0
               || (player.statuses['charisma'] || 0) !== 0
               || !!player.statuses['weak']
               || !!player.statuses['frail']
               || (player.statuses['defense'] || 0) !== 0
               || !!(combat._scalingCounters && combat._scalingCounters[card.name])
               || desc.toLowerCase().includes('wealth')
               || persistence > 0
               || !!(combat._flatAttackBonus && /melee/i.test(desc))
               || !!(targetEnemy && targetEnemy.statuses
                    && (targetEnemy.statuses['vulnerable'] || targetEnemy.statuses['bruise']));
  if (!hasMods) return desc;

  // Replace NxM damage (e.g. "Deal 3x2 Dmg")
  desc = desc.replace(/Deal (\d+)[xX](\d+) Dmg/gi, (match, d, t) => {
    const base = parseInt(d), times = parseInt(t) + (hasDuplicator ? 1 : 0);
    const computed = getCardDynamicDmg(base, card, combat, targetEnemy);
    if (computed === base && !hasDuplicator) return match;
    const col = computed > base ? '#7dff7d' : '#ff7d7d';
    const dmgStr = computed !== base ? `<span style="color:${col};font-weight:bold">${computed}</span>` : `${base}`;
    return `Deal ${dmgStr}x${times} Dmg`;
  });

  // Replace plain damage (e.g. "Deal 5 Dmg") — Duplicator adds x2 multiplier
  desc = desc.replace(/Deal (\d+) Dmg/gi, (match, d) => {
    const base = parseInt(d);
    const computed = getCardDynamicDmg(base, card, combat, targetEnemy);
    if (computed === base && !hasDuplicator) return match;
    const col = computed > base ? '#7dff7d' : '#ff7d7d';
    const dmgStr = computed !== base ? `<span style="color:${col};font-weight:bold">${computed}</span>` : `${base}`;
    return hasDuplicator ? `Deal ${dmgStr}x2 Dmg` : `Deal ${dmgStr} Dmg`;
  });

  // Replace NxM magic damage (e.g. "Deal 3x2 Magic Dmg")
  desc = desc.replace(/Deal (\d+)[xX](\d+) Magic Dmg/gi, (match, d, t) => {
    const base = parseInt(d);
    const computed = getCardDynamicMagicDmg(base, card, combat);
    if (computed === base) return match;
    const col = computed > base ? '#7dff7d' : '#ff7d7d';
    return `Deal <span style="color:${col};font-weight:bold">${computed}</span>x${t} Magic Dmg`;
  });

  // Replace plain magic damage (e.g. "Deal 5 Magic Dmg")
  desc = desc.replace(/Deal (\d+) Magic Dmg/gi, (match, d) => {
    const base = parseInt(d);
    const computed = getCardDynamicMagicDmg(base, card, combat);
    if (computed === base) return match;
    const col = computed > base ? '#7dff7d' : '#ff7d7d';
    return `Deal <span style="color:${col};font-weight:bold">${computed}</span> Magic Dmg`;
  });

  // Replace block (e.g. "Gain 5 Block" or "Gain +5 Block")
  desc = desc.replace(/Gain \+?(\d+) Block/gi, (match, b) => {
    const base = parseInt(b);
    const computed = getCardDynamicBlock(base, combat);
    if (computed === base) return match;
    const col = computed > base ? '#7dd4ff' : '#ff7d7d';
    return `Gain <span style="color:${col};font-weight:bold">${computed}</span> Block`;
  });

  // Persistence bonus: show enhanced stack count on "Apply/Inflict N Status"
  if (persistence > 0) {
    desc = desc.replace(/(?:Apply|Inflict) (\d+) ([A-Za-z_]+)/gi, (match, n, statusName) => {
      const key = statusName.toLowerCase();
      const exempt = new Set(['power', 'defense', 'arcane', 'persistence', 'energy_per_turn',
        'barricade', 'brutality', 'corruption', 'double_damage', 'no_draw']);
      if (exempt.has(key)) return match;
      const statusDef = typeof STATUSES_DATA !== 'undefined' ? STATUSES_DATA[key] : null;
      if (!statusDef || (statusDef.type !== 'Buff' && statusDef.type !== 'Debuff')) return match;
      const base = parseInt(n);
      const total = base + persistence;
      const prefix = match.startsWith('Apply') ? 'Apply' : 'Inflict';
      return `${prefix} <span style="color:#c09aff;font-weight:bold">${total}</span> ${statusName}`;
    });
  }

  return desc + itemSuffix;
}

// Lightweight re-render of just the hand zone (used when hovered enemy changes)
function refreshCombatHand() {
  const combat = window.CombatEngine && window.CombatEngine.getCombatState();
  const zone = document.getElementById('combat-hand-zone');
  if (!combat || !zone) return;
  const hand = combat.hand || [];
  const n = hand.length;
  _disposeDiceHandRenderers();
  zone.innerHTML = n === 0
    ? `<div style="color:${C.textDim};font-size:12px;text-align:center;padding-top:65px;width:100%;">No cards in hand</div>`
    : hand.map((card, i) => renderCardInHand(card, i, n, combat)).join('');
  document.querySelectorAll('.combat-hand-card').forEach(el => {
    el.addEventListener('click', () => handleCardClick(parseInt(el.dataset.handIndex)));
  });
  attachDragMouseDown();
  attachCardTooltip();
  requestAnimationFrame(() => {
    initDiceCardRenderers();
    initPendingDiceRenderers();
  });
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
  buffer:         { img: 'Buffer',        emoji: '🛡', label: 'Buffer'       },
  machine_learning: { img: 'MachineLearning', emoji: '🤖', label: 'Machine Learning' },
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
  bleed:           { img: 'Bleed',          emoji: '🩸', label: 'Bleed'           },
  bleed_thorns:    { img: 'BleedThorns',    emoji: '🩸', label: 'Bleed Thorns'    },
  // Other statuses
  blur:            { img: 'Blur',           emoji: '🌀', label: 'Blur'            },
  choked:          { img: 'Choked',         emoji: '💀', label: 'Choked'          },
  shackled:        { img: 'Shackled',        emoji: '🔒', label: 'Shackled'        },
  well_laid_plans: { img: 'Well-LaidPlans', emoji: '📋', label: 'Well-Laid Plans' },
  shiv_per_turn:   { img: null,             emoji: '🗡', label: 'Shiv/Turn'       },
  fear:           { img: 'Fear',          emoji: '😨', label: 'Fear'         },
  blind:          { img: 'Blind',         emoji: '🙈', label: 'Blind'        },
  // Temporary stat boosts (e.g. from pigment cards, "Gain +X Stat until end of combat")
  strength:       { img: null,            emoji: '💪', label: 'Strength'     },
  intelligence:   { img: null,            emoji: '🧠', label: 'Intelligence' },
  dexterity:      { img: null,            emoji: '🏃', label: 'Dexterity'    },
  charisma:       { img: null,            emoji: '✨', label: 'Charisma'     },
  // Derived combat stats
  arcane:         { img: 'Arcane',        emoji: '🔷', label: 'Arcane'       },
  persistence:    { img: 'Persistence',   emoji: '💠', label: 'Persistence'  },
  flame_barrier:  { img: 'FlameBarrier',  emoji: '🔥', label: 'Flame Barrier'},
  double_damage:  { img: 'DoubleDamage',   emoji: '⚔⚔', label: 'Double Damage'},
  enfeebled:      { img: 'Enfeebled',     emoji: '💀', label: 'Enfeebled'    },
  plated_armor:   { img: 'PlatedArmor',   emoji: '🛡', label: 'Plated Armor' },
  // Intangible (applied by Wraith Form power card)
  intangible:     { img: 'Intangible',    emoji: '👻', label: 'Intangible'   },
  // Wraith Form passive marker — shown in Powers panel, not as a status icon
  wraith_form:    { img: null,            emoji: '👻', label: 'Wraith Form'  },
  // Other active statuses
  wet:            { img: 'Wet',           emoji: '💧', label: 'Wet'          },
  no_draw:        { img: 'NoDraw',        emoji: '🚫', label: 'No Draw'      },
  burst:          { img: 'Burst',         emoji: '⚡', label: 'Burst'        },
  envenom:        { img: 'Envenom',       emoji: '☠',  label: 'Envenom'      },
  evolve:         { img: 'Evolve',        emoji: '🧬', label: 'Evolve'       },
  feel_no_pain:   { img: 'FeelNoPain',    emoji: '💪', label: 'Feel No Pain' },
  fire_breathing: { img: 'FireBreathing', emoji: '🐉', label: 'Fire Breathing'},
  corpse_explosion: { img: 'CorpseExplosion', emoji: '💀', label: 'Corpse Explosion'},
};

// ============== MAIN RENDER ENTRY POINT ==============

function renderCombatUI(combat, container) {
  if (!combat || !container) return;

  container.innerHTML = `
    <div id="combat-wrapper" style="
      flex: 1; min-height: 0; width: 100%;
      background: ${C.bg};
      display: flex; flex-direction: column;
      font-family: 'Georgia', serif;
      position: relative; overflow: hidden;
      color: ${C.text};
      user-select: none;
    ">
      ${renderItemsBar(combat)}
      ${renderTopBar(combat)}

      <div style="flex:1; display:flex; overflow:visible; position:relative; min-height:0;">
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
      padding:52px 20px 10px; gap:28px;
      min-height:0; overflow:visible;
    ">
      ${banner}
      ${combat.enemies.map(e => renderEnemyCard(e, combat)).join('')}
    </div>
  `;
}

function renderEnemyCard(enemy, combat) {
  const isDead       = enemy.health <= 0;
  const isTargeted   = combat.targetedEnemyId === enemy.id;
  const isTargeting  = !isDead && (
    (combat.selectedCardIndex !== null && combat.selectedCardIndex !== undefined)
    || !!window._pendingSpellName
  );
  const hpPct        = Math.max(0, (enemy.health / enemy.maxHealth) * 100);
  const hpColor      = hpPct > 50 ? '#27ae60' : hpPct > 25 ? '#f39c12' : '#c0392b';
  const imgSrc       = enemy.imageUrl || 'images/enemies/default.png';

  const safePattern = (enemy.pattern || '').replace(/"/g, '&quot;');
  const safeAbility = (enemy.ability || '').replace(/"/g, '&quot;');
  const safeWeight  = enemy.weight != null ? String(enemy.weight) : '';
  return `
    <div id="enemy-card-${enemy.id}"
         class="enemy-card${isTargeting ? ' enemy-targetable' : ''}"
         data-enemy-id="${enemy.id}"
         data-full-pattern="${safePattern}"
         data-full-ability="${safeAbility}"
         data-full-weight="${safeWeight}"
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
          position:absolute; top:50px; right:-14px;
          background:${C.block}; color:white;
          border-radius:50%; width:38px; height:38px;
          display:flex; align-items:center; justify-content:center;
          font-size:13px; font-weight:bold;
          border:3px solid #1a1a3a; line-height:1;
          box-shadow: 0 2px 8px rgba(0,0,0,0.7);
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
      'border-radius:8px', 'padding:10px 14px',
      'font-size:11px', 'color:#e0e0e0', 'line-height:1.6',
      'max-width:290px',
      'box-shadow:0 4px 16px rgba(0,0,0,0.7)',
      'display:none',
    ].join(';');
    document.body.appendChild(tip);
  }
}

function formatEnemyPatternLines(pattern) {
  if (!pattern) return [];
  if (/Turn \d+:/i.test(pattern)) {
    return pattern.split('|').map(s => s.trim()).filter(Boolean);
  }
  const body = pattern.replace(/^Always:\s*/i, '');
  if (body.includes('%') && body.includes('/')) {
    return ['Always:', ...body.split('/').map(s => '  ' + s.trim())];
  }
  return [pattern.trim()];
}

function showEnemyPatternTooltip(el, e) {
  const tip = document.getElementById('enemy-pattern-tooltip');
  if (!tip) return;

  const patternLines = formatEnemyPatternLines(el.dataset.fullPattern || '');
  const ability      = (el.dataset.fullAbility || '').trim();
  const weight       = (el.dataset.fullWeight  || '').trim();

  const dim   = 'color:#aaa;font-size:10px;';
  const label = 'color:#9b59b6;font-size:10px;font-weight:bold;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:3px;';
  const divider = '<div style="border-top:1px solid rgba(255,255,255,0.1);margin:7px 0;"></div>';

  let html = '';

  // Weight row
  if (weight !== '') {
    html += `<div style="${dim}">⚖ Weight: <span style="color:#f1c40f;font-weight:bold;">${weight}</span></div>`;
    html += divider;
  }

  // Pattern section
  html += `<div style="${label}">📋 Pattern</div>`;
  html += patternLines.map(line =>
    `<div style="color:#e0e0e0;">${_escHtml(line)}</div>`
  ).join('');

  // Ability section
  if (ability && ability.toUpperCase() !== 'N/A') {
    html += divider;
    html += `<div style="${label}">★ Ability</div>`;
    html += `<div style="color:#f39c12;">${_escHtml(ability)}</div>`;
  }

  tip.innerHTML = html;
  tip.style.display = 'block';
  positionEnemyPatternTooltip(e);
}

function _escHtml(s) {
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
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

function _renderSingleIntentBadge(raw, enemy, maxLen) {
  if (!raw) return '';
  const type  = getIntentType(raw);
  const style = INTENT_STYLES[type] || INTENT_STYLES.unknown;
  const { text: displayRaw, modified, modifiers } = applyIntentModifiers(raw, enemy);
  const tooltipText = modified ? `${raw} → ${displayRaw} (${modifiers.join(', ')})` : raw;
  const limit = maxLen || 36;
  const displayText = displayRaw.length > limit ? displayRaw.slice(0, limit - 2) + '…' : displayRaw;
  const powerStacks = (enemy.statuses && enemy.statuses['power']) || 0;
  const weakStacks  = (enemy.statuses && enemy.statuses['weak'])  || 0;
  const modBadge = (powerStacks !== 0 || weakStacks > 0) && type === 'attack' ? `
    <span style="font-size:9px;background:rgba(0,0,0,0.4);border-radius:6px;padding:1px 3px;color:#ffcc44;">
      ${powerStacks !== 0 ? (powerStacks > 0 ? `+${powerStacks}⚡` : `${powerStacks}⚡`) : ''}${weakStacks > 0 ? '↓' : ''}
    </span>` : '';
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
    </div>`;
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
      </div>`;
  }

  const intents = enemy.currentIntent;

  // Multi-intent (Multi Attack): render each as its own badge
  if (intents.length > 1) {
    const badges = intents
      .map(i => i.face?.raw || '')
      .filter(Boolean)
      .map(raw => _renderSingleIntentBadge(raw, enemy, 26))
      .join('');
    return `<div style="display:flex;flex-wrap:wrap;gap:2px;justify-content:center;">${badges}</div>`;
  }

  // Single intent
  const rawStr = intents[0]?.face?.raw || '';
  if (!rawStr) return '';
  return _renderSingleIntentBadge(rawStr, enemy, 38);
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

  // Highlight player zone when a self-targeting card is selected
  const selCard = (combat.selectedCardIndex !== null && combat.selectedCardIndex !== undefined)
    ? (combat.hand || [])[combat.selectedCardIndex] : null;
  const isPlayerTarget = !!(selCard
    && (selCard.type || '').toLowerCase() !== 'dice'
    && !(window.CombatEngine && window.CombatEngine.cardNeedsTarget && window.CombatEngine.cardNeedsTarget(selCard)));

  return `
    <div id="combat-player-zone" class="${isPlayerTarget ? 'player-targetable' : ''}" style="
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

        <!-- Dice board (between powers and actions) -->
        ${renderInlineeDiceBoard(combat)}

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
  const mlStacks = Array.isArray(combat.player && combat.player.statuses && combat.player.statuses.machine_learning)
    ? combat.player.statuses.machine_learning.length : 0;
  const count = (combat.powers || []).length + (mlStacks > 0 ? 1 : 0);
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

  // Build ML virtual card if player has stacks
  const mlStatuses = (combat.player && combat.player.statuses && combat.player.statuses.machine_learning) || [];
  const mlStacks = Array.isArray(mlStatuses) ? mlStatuses.length : 0;
  const mlCard = mlStacks > 0 ? [{
    name: 'Machine Learning',
    type: 'Power',
    description: `Draw 1 extra card at the start of each turn. (${mlStacks} stack${mlStacks !== 1 ? 's' : ''})`,
    imageUrl: 'images/statuses/MachineLearning.png',
    _mlStacks: mlStacks,
  }] : [];

  const allPowers = [...mlCard, ...powers];

  const cardsHTML = allPowers.length === 0
    ? `<div style="color:#888; font-size:14px; padding:20px;">No powers played this combat.</div>`
    : allPowers.map(card => {
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

function renderInlineeDiceBoard(combat) {
  const pending = (combat && combat.pendingDice) || [];

  const isDieCard = c => (c.type || '').toLowerCase() === 'dice';
  const hasDiceInDeck = combat && (
    (combat.hand        || []).some(isDieCard) ||
    (combat.drawPile    || []).some(isDieCard) ||
    (combat.discardPile || []).some(isDieCard) ||
    (combat.exhaustPile || []).some(isDieCard)
  );

  if (pending.length === 0 && !hasDiceInDeck) return '';

  const rerolls = (combat.player && combat.player.rerolls) || 0;
  const gold   = C.gold   || '#f0c850';
  const border = C.border || 'rgba(255,255,255,0.15)';

  const tilesHtml = pending.map(entry => {
    const face = entry.face || {};
    const addons  = face.addons || [];
    const isBlank = face.isBlank;
    const isCantrip   = addons.includes('cantrip');
    const isSingleUse = addons.includes('singleUse');
    const isDruid     = addons.includes('druid');
    const needsTarget = !isBlank && (face.effects || []).some(e => /^(dmg|magic_dmg|magic dmg)$/i.test(e.move || '') && !(e.addons || []).some(a => a.toLowerCase() === 'cleave'));
    const isSelected  = window._selectedPendingId === entry.id;

    const addonBadges = [
      isCantrip   ? `<span style="font-size:8px;background:#4a2c8a;color:#c09aff;border-radius:3px;padding:0 3px;">Cantrip</span>` : '',
      isSingleUse ? `<span style="font-size:8px;background:#8a2c2c;color:#ffaaaa;border-radius:3px;padding:0 3px;">1-Use</span>` : '',
      isDruid     ? `<span style="font-size:8px;background:#2c5a2c;color:#aaffaa;border-radius:3px;padding:0 3px;">Druid</span>` : '',
      needsTarget ? `<span style="font-size:8px;background:#5a3a00;color:#ffcc44;border-radius:3px;padding:0 3px;">Target</span>` : ''
    ].filter(Boolean).join(' ');

    const selectedGlow = isSelected ? `box-shadow:0 0 16px ${gold}aa;` : '';

    return `<div class="pending-die-tile" data-pending-id="${entry.id}"
      style="
        padding:4px 6px;
        background:transparent;
        border-radius:8px; cursor:${isBlank ? 'default' : 'pointer'};
        display:flex; flex-direction:column; align-items:center; gap:2px;
        ${selectedGlow}
        transition:box-shadow 0.1s;
      ">
      <div style="font-size:9px;color:#aaa;line-height:1;">${entry.cardName}</div>
      <div class="pending-dice-3d"
        data-pending-id="${entry.id}"
        data-face-num="${entry.faceIndex + 1}"
        data-card-name="${entry.cardName}"
        style="width:90px;height:90px;pointer-events:none;flex-shrink:0;">
      </div>
      <div style="font-size:10px;color:${isBlank ? '#666' : '#ddd'};text-align:center;line-height:1.2;max-width:110px;">
        ${getDiceFaceDynamicText(face, combat)}
      </div>
      <div style="display:flex;gap:2px;flex-wrap:wrap;justify-content:center;">
        ${addonBadges}
      </div>
    </div>`;
  }).join('');

  const emptyHint = pending.length === 0 ? `
    <div style="
      display:flex; align-items:center; justify-content:center;
      color:#555; font-size:11px; font-style:italic; pointer-events:none;
      padding:6px 0; min-height:36px; width:100%;
    ">play dice cards to roll</div>` : '';

  return `
    <div id="pending-dice-panel" style="
      flex:1; min-width:110px; max-width:320px;
      display:flex; flex-direction:column;
      background:rgba(0,0,0,0.35);
      border-left:1px solid ${border};
      border-right:1px solid ${border};
      padding:6px 8px;
      align-self:stretch;
    ">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:4px;flex-shrink:0;">
        <div style="font-size:10px;font-weight:bold;color:${gold};">🎲 Dice Board</div>
        ${rerolls > 0 ? `
          <button id="pending-reroll-all-btn" style="
            padding:2px 7px;
            background:#5c3a0a; border:1px solid #c07820;
            color:${gold}; border-radius:5px; font-size:9px; cursor:pointer;
          ">🔄 (${rerolls})</button>
        ` : `<div style="font-size:9px;color:#666;">No rerolls</div>`}
      </div>
      <div id="dice-board-drop-zone" style="
        display:grid;
        grid-template-columns:repeat(auto-fill,minmax(90px,1fr));
        gap:4px;
        overflow-y:auto;
        flex:1;
      ">
        ${tilesHtml}${emptyHint}
      </div>
    </div>
  `;
}

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
      <div style="display:flex; align-items:center; gap:5px; flex-wrap:wrap; justify-content:center;">
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

      <!-- Mana display (next to energy) -->
      ${(combat.player.maxMana || 0) > 0 ? `
        <div style="display:flex; align-items:center; gap:4px;">
          ${Array.from({length: combat.player.maxMana}, (_, i) => {
            const filled = i < (combat.player.mana || 0);
            return `<div style="
              width:14px; height:14px; border-radius:50%;
              background:${filled ? '#3a7bd5' : '#1a2a3a'};
              border:2px solid ${filled ? '#6ab4ff' : '#2a3a5a'};
              box-shadow:${filled ? '0 0 5px #6ab4ff88' : 'none'};
              transition:all 0.2s;
            "></div>`;
          }).join('')}
          <span style="color:#7ec8e3; font-size:11px; margin-left:2px;">💧${combat.player.mana || 0}/${combat.player.maxMana}</span>
        </div>
      ` : ''}

      <!-- End Turn button -->
      ${(() => {
        const hasMandatory = isPlayerTurn && (combat.pendingDice || []).some(
          e => (e.face && e.face.addons || []).includes('mandatory')
        );
        const bg     = !isPlayerTurn  ? 'linear-gradient(145deg,#3d3d3d,#2a2a2a)'
                     : hasMandatory   ? 'linear-gradient(145deg,#7a2a00,#4a1500)'
                     :                  'linear-gradient(145deg,#2e7d32,#1b5e20)';
        const bdr    = !isPlayerTurn  ? '#555'
                     : hasMandatory   ? '#e74c3c'
                     :                  '#4CAF50';
        const shadow = !isPlayerTurn  ? 'none'
                     : hasMandatory   ? '0 0 12px rgba(231,76,60,0.5)'
                     :                  '0 0 12px rgba(76,175,80,0.4)';
        const label  = !isPlayerTurn  ? 'Enemy Turn'
                     : hasMandatory   ? '🎲 Use Die!'
                     :                  'End Turn';
        return `<button id="combat-end-turn-btn" style="
          padding:12px 18px;
          background:${bg};
          border:3px solid ${bdr};
          border-radius:10px; color:white;
          cursor:${isPlayerTurn ? 'pointer' : 'not-allowed'};
          font-weight:bold; font-size:14px;
          width:118px;
          box-shadow:${shadow};
          transition:all 0.15s; letter-spacing:0.5px;
        " ${!isPlayerTurn ? 'disabled' : ''}>${label}</button>`;
      })()}

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

// Track active Three.js renderers for dice cards in hand so they can be disposed.
let _diceHandRenderers = [];

function _disposeDiceHandRenderers() {
  _diceHandRenderers.forEach(r => { try { r.dispose(); } catch(e) {} });
  _diceHandRenderers = [];
}

let _pendingDiceRenderers = [];

function _disposePendingDiceRenderers() {
  _pendingDiceRenderers.forEach(r => { try { r.dispose(); } catch(e) {} });
  _pendingDiceRenderers = [];
}

// Per-die color themes. sceneBg is the Three.js hex background color.
const DICE_CARD_COLORS = {
  "Isaac's D6": {
    bg: '#4d0000', inner: '#6b0000', border: '#dd2222',
    faceNum: '#ff7777', text: '#ffbbbb', outline: '#1a0000',
    sceneBg: 0x1a0000,
    cardBg: 'rgba(100,0,0,0.95)', cardBorder: '#dd2222', nameColor: '#ff9999'
  }
};
const _DICE_DEFAULT_COLORS = {
  bg: '#7a4800', inner: '#a86000', border: '#f0b030',
  faceNum: '#ffd060', text: '#ffe8a0', outline: '#3a2000',
  sceneBg: 0x1a0d00,
  cardBg: 'rgba(100,60,10,0.95)', cardBorder: '#cc8800', nameColor: '#f0c850'
};

// Color palette for S&D dice based on their tag color
const _SD_TAG_COLORS = {
  blue:   { hex: '#4488ff', sceneBg: 0x000820 },
  red:    { hex: '#ff4444', sceneBg: 0x1a0000 },
  orange: { hex: '#ff8800', sceneBg: 0x120600 },
  gray:   { hex: '#aaaaaa', sceneBg: 0x0d0d0d },
  yellow: { hex: '#ffdd00', sceneBg: 0x141000 },
};

/** Return color theme for a card. S&D dice get white-on-black with tag-colored border. */
function _getDiceColors(card) {
  if (DICE_CARD_COLORS[card.name]) return DICE_CARD_COLORS[card.name];
  if ((card.game || '').trim() === 'Slice & Dice') {
    const tags = Array.isArray(card.tags) ? card.tags : [];
    const tagEntry = tags.reduce((found, t) => found || _SD_TAG_COLORS[t], null);
    const tc = tagEntry || { hex: '#aaaaaa', sceneBg: 0x0d0d0d };
    return {
      bg: '#111111', inner: '#222222', border: tc.hex,
      faceNum: '#ffffff', text: '#ffffff', outline: '#000000',
      sceneBg: tc.sceneBg,
      cardBg: 'rgba(0,0,0,0.95)', cardBorder: tc.hex, nameColor: '#ffffff'
    };
  }
  return _DICE_DEFAULT_COLORS;
}

/**
 * Build a DICE_DATA-compatible object from a card whose type is 'Dice'.
 */
// Abbreviated face text for dice whose actual text is too long to render on a die face
const _DICE_FACE_ABBR = {
  "Isaac's D6": {
    'Random Curse, Mandatory':                                                     'Curse',
    'Random Status, Mandatory':                                                    'Status',
    'Random Skill, Mandatory':                                                     'Skill',
    'Random Attack, Mandatory':                                                    'Attack',
    'Random Power, Mandatory':                                                     'Power',
    'Random Attack, Skill, or Power that is free to play this combat, Mandatory': 'FREE!',
  },
};

function _makeDiceDataForCard(card) {
  const colors = _getDiceColors(card);
  const def = (typeof DICE_DATA !== 'undefined' ? DICE_DATA : []).find(d => d.name === card.name);
  if (def) {
    const abbr = _DICE_FACE_ABBR[card.name] || {};
    return {
      type: 'd6-card',
      colors,
      sides: def.faces.map(f => {
        const displayText = abbr[f.text] || f.text;
        return { face: f.face, text: displayText, value: f.face, displayText };
      }),
      globalModifiers: [],
      currentRoll: null
    };
  }
  // Fallback: generic 6-sided card die
  return {
    type: 'd6-card',
    colors,
    sides: Array.from({ length: 6 }, (_, i) => ({ face: i + 1, text: String(i + 1), value: i + 1, displayText: String(i + 1) })),
    globalModifiers: [],
    currentRoll: null
  };
}

/**
 * After hand HTML is injected, find `.dice-hand-3d` containers and spin up Three.js
 * renderers for each dice card. Called from attachCombatEventListeners.
 */
function initDiceCardRenderers() {
  _disposeDiceHandRenderers();
  if (typeof DiceRendererInstance === 'undefined') return;

  document.querySelectorAll('.dice-hand-3d[data-hand-index]').forEach(el => {
    const idx   = parseInt(el.dataset.handIndex);
    const combat = window.CombatEngine && window.CombatEngine.getCombatState();
    if (!combat) return;
    const card = combat.hand[idx];
    if (!card) return;

    // Ensure the container has real dimensions before starting Three.js
    if (el.clientWidth === 0 || el.clientHeight === 0) {
      el.style.minHeight = '60px';
    }

    const diceData = _makeDiceDataForCard(card);
    const r = new DiceRendererInstance();
    r.init(el, diceData.colors.sceneBg || 0x1a0d00);
    r.createDice(diceData);
    _diceHandRenderers.push(r);

    // Spin die on hover as a visual preview (purely cosmetic, no game effect)
    const parentCard = el.closest('.combat-hand-card');
    if (parentCard) {
      let _hoverRollTimer = null;
      // Only trigger spin when the player is actively hovering (not mid-drag)
      parentCard.addEventListener('mouseenter', () => {
        if (_dragState && _dragState.moved) return; // skip during drag
        clearTimeout(_hoverRollTimer);
        _hoverRollTimer = setTimeout(() => {
          if (!r.isRolling) {
            const faceNum = Math.floor(Math.random() * (diceData.sides ? diceData.sides.length : 6)) + 1;
            r.rollDice(diceData, faceNum, null);
          }
        }, 200);
      });
      parentCard.addEventListener('mouseleave', () => {
        clearTimeout(_hoverRollTimer);
      });
    }
  });
}

function initPendingDiceRenderers() {
  _disposePendingDiceRenderers();
  if (typeof DiceRendererInstance === 'undefined') return;

  document.querySelectorAll('.pending-dice-3d[data-pending-id]').forEach(el => {
    const faceNum   = parseInt(el.dataset.faceNum) || 1;
    const cardName  = el.dataset.cardName || '';

    const srcCard = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.find(c => c.name === cardName) : null;
    const diceData = srcCard ? _makeDiceDataForCard(srcCard) : null;
    if (!diceData) return;

    if (el.clientWidth === 0 || el.clientHeight === 0) {
      el.style.width  = '66px';
      el.style.height = '66px';
    }

    const r = new DiceRendererInstance();
    r.init(el, diceData.colors ? diceData.colors.sceneBg : 0x0d0800);
    r.createDice(diceData);
    r.rollDice(diceData, faceNum, null);
    _pendingDiceRenderers.push(r);
  });
}

/**
 * Render a dice-type card in hand as a 3D die (instead of a flat card).
 */
function renderDiceCardInHand(card, index, total, combat) {
  const isSelected   = combat.selectedCardIndex === index;
  const isPlayerTurn = combat.phase === 'player_action';
  const effectiveCost = (window.CombatEngine && window.CombatEngine.getEffectiveCost)
    ? window.CombatEngine.getEffectiveCost(card)
    : (card._freeCost ? 0 : card.cost);
  const canAfford = (typeof effectiveCost === 'number' ? effectiveCost : card.cost) <= (combat.player.energy || 0);
  const costColor = canAfford ? '#ffd700' : '#e74c3c';

  let cardW, cardH, marginL, orbW, namePx;
  if (total <= 5)      { cardW = 110; cardH = 160; marginL = -28; orbW = 31; namePx = 11; }
  else if (total <= 7) { cardW = 96;  cardH = 142; marginL = -22; orbW = 29; namePx = 10; }
  else if (total <= 9) { cardW = 84;  cardH = 124; marginL = -18; orbW = 27; namePx = 9.5;}
  else                 { cardW = 74;  cardH = 110; marginL = -14; orbW = 25; namePx = 9;  }

  const t        = total <= 1 ? 0 : (index - (total - 1) / 2) / ((total - 1) / 2);
  const maxAngle = Math.min(4 * (total - 1), 24);
  const rotation = t * (maxAngle / 2);
  const yLift    = (1 - Math.abs(t)) * 7;

  const baseTransform = `rotate(${rotation}deg) translateY(${-yLift}px)`;
  const selTransform  = `rotate(${rotation * 0.3}deg) translateY(-30px) scale(1.18)`;
  const hoverTrans    = `rotate(${rotation * 0.2}deg) translateY(-50px) scale(1.42)`;

  const diceColors = _getDiceColors(card);
  const borderColor  = diceColors.cardBorder;
  const bgColor      = diceColors.cardBg;
  const nameColor    = diceColors.nameColor;
  const boxShadow   = isSelected
    ? `0 0 20px ${C.goldBright}bb, 0 0 6px ${borderColor}88`
    : `0 4px 10px rgba(0,0,0,0.6), inset 0 1px 0 rgba(255,255,255,0.06)`;
  const activeBorder = isSelected ? C.goldBright : borderColor;
  const ml = index > 0 ? `margin-left:${marginL}px;` : '';

  const hoJS  = `this.style.transform='${hoverTrans}';this.style.zIndex='95';this.style.boxShadow='0 10px 30px rgba(0,0,0,0.8),0 0 16px ${borderColor}99';`;
  const hoOut = `this.style.transform='${isSelected ? selTransform : baseTransform}';this.style.zIndex='${isSelected ? 90 : 20 + index}';this.style.boxShadow='${boxShadow}';`;

  // Build tooltip showing all faces
  const faceDef = (typeof DICE_DATA !== 'undefined' ? DICE_DATA : []).find(d => d.name === card.name);
  const facesHtml = faceDef
    ? faceDef.faces.map(f => `${f.face}: ${f.text}`).join('\n')
    : '';

  return `
    <div class="combat-hand-card" data-hand-index="${index}"
      title="${facesHtml}"
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
      ">${effectiveCost}</div>

      <!-- 3D die container -->
      <div class="dice-hand-3d" data-hand-index="${index}" style="
        width:100%; flex:1; min-height:0;
      "></div>

      <!-- Name -->
      <div style="
        padding:2px 4px 3px;
        font-size:${namePx}px; font-weight:700; color:${nameColor};
        text-align:center; line-height:1.2; flex-shrink:0;
        text-shadow:0 1px 3px rgba(0,0,0,0.9);
        border-top:1px solid ${borderColor}55;
        background:rgba(0,0,0,0.35);
      ">${card.name}${card.upgraded ? `<span style="color:#4CAF50;font-weight:bold;">+</span>` : ''}</div>
    </div>
  `;
}

function renderCardInHand(card, index, total, combat) {
  // Dice-type cards render as 3D dice
  if ((card.type || '').toLowerCase() === 'dice') {
    return renderDiceCardInHand(card, index, total, combat);
  }

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
    cardW = 110; cardH = 160; marginL = -28; artH = 68; namePx = 11; descPx = 9.5; orbW = 31;
  } else if (total <= 7) {
    cardW = 96;  cardH = 142; marginL = -22; artH = 58; namePx = 10; descPx = 8.5; orbW = 29;
  } else if (total <= 9) {
    cardW = 84;  cardH = 124; marginL = -18; artH = 50; namePx = 9.5; descPx = 7.5; orbW = 27;
  } else {
    cardW = 74;  cardH = 110; marginL = -14; artH = 44; namePx = 9;   descPx = 7;   orbW = 25;
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
      ">${card.name}${card.upgraded ? `<span style="color:#4CAF50;font-weight:bold;">+</span>` : ''}</div>

      <!-- Divider -->
      <div style="height:1px; background:linear-gradient(90deg,transparent,${borderColor}88,transparent); margin:1px 3px; flex-shrink:0;"></div>

      <!-- Description -->
      <div style="
        flex:1; padding:2px 4px;
        font-size:${descPx}px; color:${card.upgraded ? '#4CAF50' : '#ccc'};
        text-align:center; line-height:1.35;
        overflow-y:auto; overflow-x:hidden;
        scrollbar-width:thin; scrollbar-color:rgba(255,255,255,0.2) transparent;
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
  const activeTab = window._combatLogTab || 'log';
  const spells    = (combat && combat.spells) || [];
  const player    = (combat && combat.player) || {};

  const logs    = (combat.log || []).slice(-40);
  const logHTML = logs.map(entry => {
    const color = { info:C.textDim, success:'#4CAF50', warning:'#f39c12', danger:'#e74c3c' }[entry.type] || C.text;
    return `<div style="
      padding:2px 8px; font-size:11px; color:${color};
      border-bottom:1px solid rgba(255,255,255,0.04); line-height:1.45;
    ">${entry.message}</div>`;
  }).join('');

  const _SPELL_ELEMENTS = ['Fire','Water','Poison','Earth','Dark','Blood','Electric','Ice','Thunder','Wind'];
  const _ELEMENT_COLOR  = {fire:'#ff6b35',water:'#4488ff',poison:'#44bb44',earth:'#88aa44',dark:'#a855f7',blood:'#cc2222',electric:'#ffcc00',ice:'#88ddff',thunder:'#ffcc00',wind:'#aaddcc'};
  const _ELEMENT_ICON   = {fire:'🔥',water:'💧',poison:'☠',earth:'🌿',dark:'🌑',blood:'🩸',electric:'⚡',ice:'❄',thunder:'⚡',wind:'💨'};
  const _spellElement = sp => {
    const el = sp.element;
    if (el && el !== 'N/A') return el;
    for (const eff of (sp.effects || [])) {
      for (const addon of (eff.addons || [])) {
        if (_SPELL_ELEMENTS.includes(addon)) return addon;
      }
    }
    return null;
  };

  const spellsHtml = spells.length === 0
    ? `<div style="color:${C.textDim};font-size:11px;padding:16px 8px;text-align:center;">No spells learned yet.<br><span style="font-size:9px;color:#444;">Buy hero dice cards to learn spells.</span></div>`
    : spells.map(sp => {
        const mana = sp.cost !== undefined ? sp.cost : (sp.manaCost || 0);
        const cdLeft = combat.spellCooldowns && combat.spellCooldowns[sp.name] > 0 ? combat.spellCooldowns[sp.name] : 0;
        const onCd = cdLeft > 0;
        const usedSingle = !!(sp.keywords && sp.keywords.includes('SingleCast') && combat.usedSingleCast && combat.usedSingleCast[sp.name]);
        const noMana = (combat.player.mana || 0) < mana;
        const wrongPhase = combat.phase !== 'player_action';
        const canCast = !onCd && !usedSingle && !noMana && !wrongPhase;
        const statusText = onCd ? `CD: ${cdLeft}` : usedSingle ? 'Used' : noMana ? 'No Mana' : wrongPhase ? 'Wait' : '';
        const imgSrc = sp.imageUrl || sp.image || '';
        const rarityColor = ({Rare:'#9b59b6', Uncommon:'#4CAF50', Common:'#aaa'})[sp.rarity] || '#888';
        const el = _spellElement(sp);
        const elKey = el ? el.toLowerCase() : null;
        const elColor = elKey ? (_ELEMENT_COLOR[elKey] || '#888') : null;
        const elIcon  = elKey ? (_ELEMENT_ICON[elKey]  || '✦')   : null;
        return `<div style="
          display:flex;flex-direction:column;gap:0;
          margin:6px 6px 0;border-radius:8px;overflow:hidden;
          border:1px solid ${canCast ? '#7c3aed' : 'rgba(255,255,255,0.1)'};
          background:${canCast ? 'rgba(124,58,237,0.12)' : 'rgba(0,0,0,0.3)'};
          opacity:${canCast ? '1' : '0.55'};
          transition:border-color 0.15s,background 0.15s;
        "
        onmouseover="${canCast ? "this.style.borderColor='#a78bfa';this.style.background='rgba(124,58,237,0.22)'" : ''}"
        onmouseout="${canCast ? "this.style.borderColor='#7c3aed';this.style.background='rgba(124,58,237,0.12)'" : ''}">
          <div style="display:flex;align-items:center;gap:7px;padding:6px 7px 4px;">
            ${imgSrc ? `<img src="${imgSrc}" alt="${sp.name}" style="width:34px;height:34px;object-fit:contain;border-radius:4px;background:rgba(0,0,0,0.4);border:1px solid ${rarityColor}44;flex-shrink:0;" onerror="this.style.opacity='0.2'">` : `<div style="width:34px;height:34px;border-radius:4px;background:#1a1a2e;flex-shrink:0;"></div>`}
            <div style="flex:1;min-width:0;">
              <div style="font-weight:bold;font-size:11px;color:#e9d5ff;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;">${sp.name}</div>
              <div style="display:flex;align-items:center;gap:4px;margin-top:2px;flex-wrap:wrap;">
                <span style="font-size:9px;font-weight:bold;color:#6ab4ff;background:rgba(99,102,241,0.2);border:1px solid #6366f155;border-radius:8px;padding:1px 5px;">💧${mana}</span>
                ${sp.rarity ? `<span style="font-size:8px;color:${rarityColor};text-transform:uppercase;font-weight:bold;">${sp.rarity}</span>` : ''}
                ${el ? `<span style="font-size:8px;font-weight:bold;color:${elColor};background:${elColor}22;border:1px solid ${elColor}44;border-radius:6px;padding:1px 4px;">${elIcon} ${el}</span>` : ''}
              </div>
            </div>
          </div>
          <div style="font-size:9px;color:#bbb;padding:0 7px 5px;line-height:1.45;">${sp.description || ''}</div>
          <div style="padding:0 7px 6px;">
            ${canCast
              ? (() => {
                  const isPending = window._pendingSpellName === sp.name;
                  const needsTarget = window.CombatEngine && window.CombatEngine.spellNeedsTarget
                    ? window.CombatEngine.spellNeedsTarget(sp) : false;
                  const bg = isPending
                    ? 'linear-gradient(135deg,#dc2626,#b91c1c)'
                    : 'linear-gradient(135deg,#7c3aed,#6d28d9)';
                  const label = isPending ? '✖ Cancel' : needsTarget ? '🎯 Target' : '✨ Cast';
                  return `<button onclick="window._handleSpellbookCast && window._handleSpellbookCast('${sp.name}')"
                    style="width:100%;padding:4px 0;background:${bg};border:none;border-radius:5px;
                      color:white;font-size:10px;font-weight:bold;cursor:pointer;letter-spacing:0.5px;">
                    ${label}
                  </button>`;
                })()
              : `<div style="width:100%;padding:3px 0;background:rgba(255,255,255,0.05);border-radius:5px;
                  color:#666;font-size:9px;font-weight:bold;text-align:center;">${statusText}</div>`
            }
          </div>
        </div>`;
      }).join('');

  // Stats tab
  const statRow = (label, value, color) =>
    `<div style="display:flex;justify-content:space-between;align-items:center;
      padding:3px 10px;font-size:11px;border-bottom:1px solid rgba(255,255,255,0.04);">
      <span style="color:${C.textDim};">${label}</span>
      <span style="color:${color || C.text};font-weight:bold;">${value}</span>
    </div>`;
  const section = (title) =>
    `<div style="font-size:10px;font-weight:bold;color:${C.gold};
      padding:5px 10px 3px;background:rgba(255,255,255,0.04);
      border-bottom:1px solid ${C.border};border-top:1px solid ${C.border};
      margin-top:2px;">${title}</div>`;

  const activeStatuses = Object.entries(player.statuses || {})
    .filter(([, v]) => (Array.isArray(v) ? v.length : v) > 0);

  const statsHtml = `
    ${section('⚔ Combat')}
    ${statRow('Health', `${player.health || 0} / ${player.maxHealth || 0}`, '#e74c3c')}
    ${statRow('Block',  player.block || 0, '#2980b9')}
    ${statRow('Energy', `${player.energy || 0} / ${player.maxEnergy || 0}`, '#f1c40f')}
    ${(player.maxMana || 0) > 0 ? statRow('Mana', `${player.mana || 0} / ${player.maxMana}`, '#6ab4ff') : ''}
    ${(player.rerolls || 0) > 0 ? statRow('Rerolls', player.rerolls, C.dice) : ''}
    ${section('🃏 Deck')}
    ${statRow('Hand',     (combat.hand        || []).length, C.textDim)}
    ${statRow('Draw',     (combat.drawPile    || []).length, C.textDim)}
    ${statRow('Discard',  (combat.discardPile || []).length, C.textDim)}
    ${statRow('Exhaust',  (combat.exhaustPile || []).length, C.textDim)}
    ${section('🌟 Base Stats')}
    ${statRow('Strength',     window.strength     || 0, '#e74c3c')}
    ${statRow('Dexterity',    window.dexterity    || 0, '#3498db')}
    ${statRow('Intelligence', window.intelligence || 0, '#9b59b6')}
    ${statRow('Charisma',     window.charisma     || 0, '#f1c40f')}
    ${activeStatuses.length > 0 ? `
      ${section('✨ Statuses')}
      ${activeStatuses.map(([k, v]) => {
        const meta = STATUS_META[k];
        const label = meta ? `${meta.emoji} ${meta.label}` : k;
        const val   = Array.isArray(v) ? v.length : v;
        return statRow(label, val, '#aaa');
      }).join('')}
    ` : ''}
  `;

  const tabStyle = (tab) => `
    flex:1; padding:5px 0; font-size:10px; font-weight:bold;
    text-align:center; cursor:pointer;
    color:${activeTab === tab ? C.gold : C.textDim};
    border-bottom:2px solid ${activeTab === tab ? C.gold : 'transparent'};
    background:${activeTab === tab ? 'rgba(255,255,255,0.05)' : 'transparent'};
    transition:all 0.1s;
  `;
  const switchTab = (tab) =>
    `window._combatLogTab='${tab}';window.CombatUI&&window.CombatUI.updateCombatDisplay&&window.CombatUI.updateCombatDisplay()`;

  const lootHtml = _buildCombatLootHtml();

  return `
    <div id="combat-log-panel" style="
      width:220px; flex-shrink:0;
      background:rgba(0,0,0,0.55);
      border-left:2px solid ${C.border};
      display:flex; flex-direction:column;
    ">
      <div style="display:flex;border-bottom:1px solid ${C.border};flex-shrink:0;">
        <div style="${tabStyle('log')}"       onclick="${switchTab('log')}">📜 Log</div>
        <div style="${tabStyle('spellbook')}" onclick="${switchTab('spellbook')}">✨ Spells</div>
        <div style="${tabStyle('stats')}"     onclick="${switchTab('stats')}">📊 Stats</div>
        <div style="${tabStyle('loot')}"      onclick="${switchTab('loot')}">🧪 Loot</div>
      </div>
      <div id="combat-log-entries" style="
        flex:1; overflow-y:auto;
        display:flex; flex-direction:column${activeTab === 'log' ? '-reverse' : ''};
        padding:4px 0;
        scrollbar-width:thin;
        scrollbar-color:${C.border} transparent;
      ">
        ${activeTab === 'log' ? logHTML : activeTab === 'spellbook' ? spellsHtml : activeTab === 'loot' ? lootHtml : statsHtml}
      </div>
    </div>
  `;
}

function _buildCombatLootHtml() {
  const loot = (typeof gameState !== 'undefined' && gameState.loot) ? gameState.loot : [];
  const potions = loot.map((l, i) => ({ ...l, _idx: i })).filter(l => l.type === 'potion');

  if (potions.length === 0) {
    return `<div style="padding:14px;color:#666;font-size:11px;text-align:center;font-style:italic;">No potions in loot.</div>`;
  }

  return potions.map(item => {
    const data = typeof POTIONS_DATA !== 'undefined' ? POTIONS_DATA.find(p => p.name === item.name) : null;
    const displayName = typeof getPotionDisplayName === 'function' ? getPotionDisplayName(item.name) : item.name;
    const imgPath = (data && typeof getPotionImagePath === 'function') ? getPotionImagePath(data) : 'images/potions/Unidentified.png';
    const isId = typeof isPotionIdentified === 'function' ? isPotionIdentified(item.name) : false;
    const effectText = (isId && data) ? data.effect : '???';
    const rarityColor = typeof _rarityColor === 'function' ? _rarityColor(item.rarity) : '#aaa';

    return `
      <div style="padding:8px;border-bottom:1px solid rgba(255,255,255,0.06);display:flex;gap:8px;align-items:center;">
        <img src="${imgPath}" style="width:36px;height:36px;object-fit:contain;flex-shrink:0;"
          onerror="this.src='images/potions/Unidentified.png'">
        <div style="flex:1;min-width:0;">
          <div style="color:#6ab4ff;font-size:11px;font-weight:bold;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${displayName}</div>
          <div style="color:${rarityColor};font-size:10px;">${item.rarity}</div>
          <div style="color:#999;font-size:10px;font-style:italic;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${effectText}</div>
        </div>
        <button onclick="usePotionFromLoot(${item._idx})" style="
          padding:4px 8px;background:#3498db;border:none;border-radius:4px;
          color:white;font-size:10px;font-weight:bold;cursor:pointer;flex-shrink:0;"
          onmouseenter="this.style.background='#2980b9'" onmouseleave="this.style.background='#3498db'">
          Use
        </button>
      </div>
    `;
  }).join('');
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
  // Some STATUSES_DATA entries use a suffix (e.g. multi_attack_x for multi_attack)
  const data = (typeof STATUSES_DATA !== 'undefined')
    ? (STATUSES_DATA[key] || STATUSES_DATA[key + '_x'] || null)
    : null;
  const meta = STATUS_META[key] || { emoji: '•', label: key };
  const name = data ? data.name.replace(/ X$/, ` ${val}`) : meta.label;
  const desc = data ? data.description.replace(/\bX\b/g, val) : '';
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
    if (k === 'machine_learning') return; // shown in Powers overlay instead
    if (k === 'wraith_form') return;      // passive marker — shown in Powers panel only
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

  // Init Three.js renderers for dice cards in hand and pending tiles
  requestAnimationFrame(() => {
    initDiceCardRenderers();
    initPendingDiceRenderers();
  });

  // End turn button
  const endBtn = document.getElementById('combat-end-turn-btn');
  if (endBtn) {
    endBtn.addEventListener('click', () => {
      if (!window.CombatEngine) return;
      const snap   = captureHPSnapshot(window.CombatEngine.getCombatState());
      const result = window.CombatEngine.endTurn();
      if (result && result.error === 'mandatory_die') {
        if (typeof createNotification === 'function') {
          createNotification(`Must use ${result.dieName || 'pending die'} before ending turn!`, '#e74c3c', '🎲');
        }
        return;
      }
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
            // If WLP also pending, it will be chained inside the modal's confirm handler
          }
        } else if (combat && combat._pendingRetainPick) {
          // Well-Laid Plans: no other picker pending, show retain picker directly
          const rp = combat._pendingRetainPick;
          combat._pendingRetainPick = null;
          if (typeof window.showCardPickerModal === 'function') {
            window.showCardPickerModal({ action: 'retain', pile: 'hand', count: rp.count });
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

  // Pending dice tiles
  document.querySelectorAll('.pending-die-tile').forEach(el => {
    el.addEventListener('click', () => {
      const cs = window.CombatEngine && window.CombatEngine.getCombatState();
      if (!cs || cs.phase !== 'player_action') return;
      const id = el.dataset.pendingId;
      const entry = cs.pendingDice.find(e => e.id === id);
      if (!entry) return;
      const face = entry.face || {};
      if (face.isaacsTransform) {
        // Isaac's D6: show card picker then apply transform
        window._selectedPendingId = null;
        _showIsaacTransformPicker(face, cs, id);
        return;
      }
      if (face.isBlank) {
        // Dismiss blank
        window.CombatEngine.usePendingDie(id, null);
        window._selectedPendingId = null;
        updateCombatDisplay();
        checkCombatEnd();
        return;
      }
      const needsTarget = (face.effects || []).some(e => /^(dmg|magic_dmg|magic dmg)$/i.test(e.move || '') && !(e.addons || []).some(a => a.toLowerCase() === 'cleave'));
      if (needsTarget) {
        // If a target is already selected (or there's only one enemy), fire immediately
        const living = (cs.enemies || []).filter(e => e.health > 0);
        const autoTarget = cs.targetedEnemyId || (living.length === 1 ? living[0].id : null);
        if (autoTarget) {
          window._selectedPendingId = null;
          const snap = captureHPSnapshot(cs);
          window.CombatEngine.usePendingDie(id, autoTarget);
          showHPDiffs(snap, cs);
          updateCombatDisplay();
          checkCombatEnd();
        } else {
          // Toggle selection and wait for enemy click
          window._selectedPendingId = (window._selectedPendingId === id) ? null : id;
          updateCombatDisplay();
        }
      } else {
        // Apply immediately
        window._selectedPendingId = null;
        const snap = captureHPSnapshot(cs);
        window.CombatEngine.usePendingDie(id, null);
        showHPDiffs(snap, cs);
        updateCombatDisplay();
        checkCombatEnd();
      }
    });

    // Drag die tile to enemy
    el.addEventListener('mousedown', e => {
      if (e.button !== 0) return;
      const cs = window.CombatEngine && window.CombatEngine.getCombatState();
      if (!cs || cs.phase !== 'player_action') return;
      const id = el.dataset.pendingId;
      const entry = cs.pendingDice.find(en => en.id === id);
      if (!entry) return;
      const face = entry.face || {};
      const needsTarget = !face.isBlank && (face.effects || []).some(ef => /^(dmg|magic_dmg|magic dmg)$/i.test(ef.move || '') && !(ef.addons || []).some(a => a.toLowerCase() === 'cleave'));
      if (!needsTarget) return; // non-targeting tiles don't need drag
      e.stopPropagation();
      const rect = el.getBoundingClientRect();
      _dragState = {
        isDieTile: true,
        pendingId: id,
        tileEl: el,
        startX: e.clientX,
        startY: e.clientY,
        offsetX: e.clientX - rect.left,
        offsetY: e.clientY - rect.top,
        clone: null,
        moved: false,
        hoveredEnemy: null,
        cardEl: null,
        isDice: false
      };
    });
  });

  // Reroll All button
  const rerollAllBtn = document.getElementById('pending-reroll-all-btn');
  if (rerollAllBtn) {
    rerollAllBtn.addEventListener('click', () => {
      if (!window.CombatEngine) return;
      const result = window.CombatEngine.rerollAllPending();
      if (result && result.success) {
        updateCombatDisplay();
      } else if (result && result.error) {
        typeof createNotification === 'function' &&
          createNotification(result.error, '#e74c3c', '🎲');
      }
    });
  }

  // Player zone click: confirm a selected self-targeting / power card
  const playerZone = document.getElementById('combat-player-zone');
  if (playerZone) {
    playerZone.addEventListener('click', () => {
      const cs = window.CombatEngine && window.CombatEngine.getCombatState();
      if (!cs || cs.phase !== 'player_action') return;
      const idx = cs.selectedCardIndex;
      if (idx === null || idx === undefined) return;
      const card = (cs.hand || [])[idx];
      if (!card) return;
      const needsEnemy = window.CombatEngine.cardNeedsTarget ? window.CombatEngine.cardNeedsTarget(card) : false;
      if (needsEnemy || (card.type || '').toLowerCase() === 'dice') return;
      _playSelectedSelfCard(cs, idx);
    });
  }
}

function handleEnemyClick(enemyId) {
  const combat = window.CombatEngine && window.CombatEngine.getCombatState();
  if (!combat) return;

  // Pending spell targeting: cast the queued spell against this enemy
  if (window._pendingSpellName) {
    const spellName = window._pendingSpellName;
    window._pendingSpellName = null;
    const result = window.CombatEngine.castSpell
      ? window.CombatEngine.castSpell(spellName, { enemyId })
      : { success: false };
    if (result && !result.success && result.error) {
      typeof createNotification === 'function' &&
        createNotification(result.error, '#e74c3c', '✨');
    }
    updateCombatDisplay();
    checkCombatEnd();
    return;
  }

  // Pending die targeting: if a pending die tile is selected and needs a target
  if (window._selectedPendingId) {
    const pendingId = window._selectedPendingId;
    window._selectedPendingId = null;
    const snap = captureHPSnapshot(combat);
    window.CombatEngine.usePendingDie(pendingId, enemyId);
    showHPDiffs(snap, combat);
    updateCombatDisplay();
    checkCombatEnd();
    return;
  }

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

  // Dice-type cards: select/deselect only — drag to the Dice Board to roll
  if ((card.type || '').toLowerCase() === 'dice') {
    combat.selectedCardIndex = combat.selectedCardIndex === index ? null : index;
    refreshCombatHand();
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
    refreshCombatHand();
  } else {
    // Self-targeting / power cards: select first, then click player zone to confirm
    if (combat.selectedCardIndex === index) {
      combat.selectedCardIndex = null;
    } else {
      combat.selectedCardIndex = index;
    }
    refreshCombatHand();
  }
}

function _playSelectedSelfCard(combat, idx) {
  const snap = captureHPSnapshot(combat);
  const result = window.CombatEngine.playCard(idx, null);
  if (result && result.success) {
    const hitLog = [...(combat._hitLog || [])];
    combat._hitLog = [];
    combat.selectedCardIndex = null;
    animateCardPlay(idx, null, () => {
      showHPDiffs(snap, combat, hitLog.length > 0);
      checkAndFlashReshuffle(snap, combat);
      replayHits(hitLog, () => {
        updateCombatDisplay();
        checkCombatEnd();
      });
    });
    updateCombatDisplay();
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
    @keyframes playerTargetPulse {
      0%,100% { box-shadow: 0 0 0 2px rgba(74,175,80,0.4); }
      50%      { box-shadow: 0 0 0 5px rgba(74,175,80,0.8), 0 0 22px rgba(74,175,80,0.4); }
    }
    .player-targetable { animation: playerTargetPulse 1s ease-in-out infinite; cursor: pointer !important; }
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
      const sourceEl = _dragState.cardEl || _dragState.tileEl;
      if (sourceEl) sourceEl.style.opacity = '0.3';

      // Build clone from live DOM element (card or die tile)
      const rect  = sourceEl ? sourceEl.getBoundingClientRect() : { width: 80, height: 80 };
      const clone = sourceEl ? sourceEl.cloneNode(true) : document.createElement('div');
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

    // Highlight enemy under cursor while dragging — use elementFromPoint (O(1)) instead of
    // querying every enemy card and calling getBoundingClientRect on each (O(n) per frame)
    if (_dragState.moved) {
      const pointEl = document.elementFromPoint(e.clientX, e.clientY)?.closest('.enemy-card');
      if (pointEl !== _dragState.hoveredEnemy) {
        if (_dragState.hoveredEnemy) _dragState.hoveredEnemy.style.outline = '';
        if (pointEl) pointEl.style.outline = `3px solid ${C.goldBright}`;
        _dragState.hoveredEnemy = pointEl || null;
      }

      // Highlight Dice Board when dragging a dice card over it
      if (_dragState.isDice) {
        const overBoard = !!document.elementFromPoint(e.clientX, e.clientY)?.closest('#pending-dice-panel');
        const panel = document.getElementById('pending-dice-panel');
        if (panel) {
          if (overBoard) {
            panel.style.background = 'rgba(240,200,80,0.18)';
            panel.style.borderTopColor = C.goldBright;
          } else {
            panel.style.background = '';
            panel.style.borderTopColor = '';
          }
        }
      }
    }
  });

  // --- Mouse up: play card on enemy drop or cancel ---
  document.addEventListener('mouseup', e => {
    if (!_dragState) return;
    const { cardIndex, clone, moved, cardEl, isDieTile, pendingId, tileEl } = _dragState;
    _dragState = null;
    if (clone)   clone.remove();
    if (cardEl)  cardEl.style.opacity = '';
    if (tileEl)  tileEl.style.opacity = '';
    document.querySelectorAll('.enemy-card').forEach(el => el.style.outline = '');

    // Reset dice board highlight
    const dicePanel = document.getElementById('pending-dice-panel');
    if (dicePanel) { dicePanel.style.background = ''; dicePanel.style.borderTopColor = ''; }

    if (!moved) return; // not a drag — click handler will fire

    const combat = window.CombatEngine && window.CombatEngine.getCombatState();
    if (!combat || combat.phase !== 'player_action') return;

    // Pending die tile drag → drop on enemy
    if (isDieTile) {
      const enemyEl = document.elementFromPoint(e.clientX, e.clientY)?.closest('.enemy-card');
      if (enemyEl) {
        window._selectedPendingId = null;
        const snap = captureHPSnapshot(combat);
        window.CombatEngine.usePendingDie(pendingId, enemyEl.dataset.enemyId);
        showHPDiffs(snap, combat);
        updateCombatDisplay();
        checkCombatEnd();
      }
      return;
    }

    const card = (combat.hand || [])[cardIndex];
    if (!card) return;

    const canAfford  = card.cost !== 'No' && (card.cost === 'X' || (card.cost || 0) <= (combat.player.energy || 0));
    if (!canAfford) return;

    const needsTarget = window.CombatEngine.cardNeedsTarget
      ? window.CombatEngine.cardNeedsTarget(card) : false;

    if ((card.type || '').toLowerCase() === 'dice') {
      // Only play when dropped on the Dice Board; cancel silently otherwise
      const onBoard = !!document.elementFromPoint(e.clientX, e.clientY)?.closest('#pending-dice-panel');
      if (onBoard) handleDiceCardPlay(cardIndex, combat);
    } else if (needsTarget) {
      // Must drop on an enemy
      const enemyEl = document.elementFromPoint(e.clientX, e.clientY)
                        ?.closest('.enemy-card');
      if (enemyEl) {
        combat.selectedCardIndex = cardIndex;
        handleEnemyClick(enemyEl.dataset.enemyId);
      }
      // Dropped elsewhere — cancel silently
    } else {
      // Non-targeted: play on drop — but cancel if the card is dragged back over the hand
      const droppedOnHand = !!document.elementFromPoint(e.clientX, e.clientY)?.closest('#combat-hand-zone');
      if (droppedOnHand) return;
      const result = window.CombatEngine.playCard(cardIndex, null);
      if (result && result.success) {
        combat.selectedCardIndex = null;
        updateCombatDisplay();
        checkCombatEnd();
      }
    }
  });

  // --- Escape: cancel card selection or pending spell targeting ---
  document.addEventListener('keydown', e => {
    if (e.key !== 'Escape') return;
    const combat = window.CombatEngine && window.CombatEngine.getCombatState();
    let needsRedraw = false;
    if (combat && combat.selectedCardIndex !== null && combat.selectedCardIndex !== undefined) {
      combat.selectedCardIndex = null;
      needsRedraw = true;
    }
    if (window._pendingSpellName) {
      window._pendingSpellName = null;
      needsRedraw = true;
    }
    if (needsRedraw) updateCombatDisplay();
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
      const combat  = window.CombatEngine && window.CombatEngine.getCombatState();
      const card    = combat ? (combat.hand || [])[parseInt(el.dataset.handIndex)] : null;
      const isDice  = card ? (card.type || '').toLowerCase() === 'dice' : false;
      _dragState = {
        cardIndex: parseInt(el.dataset.handIndex),
        cardEl:    el,
        clone:     null,
        moved:     false,
        isDice,
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
              // Show damage preview if the enemy or player has relevant statuses
              const dmgMatch = (card.description || '').match(/Deal (\d+)(?:[xX](\d+))? Dmg/i);
              if (!dmgMatch) return '';
              const base = parseInt(dmgMatch[1]);
              const baseNoTarget = getCardDynamicDmg(base, card, combat, null);
              const withTarget = _ttEnemy ? getCardDynamicDmg(base, card, combat, _ttEnemy) : baseNoTarget;
              const playerStatuses = combat && combat.player && combat.player.statuses || {};
              const vuln = _ttEnemy && _ttEnemy.statuses && _ttEnemy.statuses['vulnerable'];
              const bruse = _ttEnemy && _ttEnemy.statuses && _ttEnemy.statuses['bruise'];
              const weak = playerStatuses['weak'];
              const dblDmg = playerStatuses['double_damage'];
              const hasModifier = vuln || bruse || weak || dblDmg;
              if (!hasModifier) return '';
              // Compare vs base (no player or enemy buffs)
              const rawBase = getCardDynamicDmg(base, { ...card, description: (card.description||'').replace(/Wealth/gi,'') }, { player: { statuses: {} } }, null);
              if (withTarget === base && !hasModifier) return '';
              const tags = [];
              if (weak) tags.push('🔻 Weak');
              if (dblDmg) tags.push('⚔⚔ Double Dmg');
              if (vuln) tags.push('💢 Vulnerable');
              if (bruse) tags.push(`🩹 Bruise ×${_ttEnemy.statuses['bruise']}`);
              const label = _ttEnemy ? `vs ${_ttEnemy.name}` : 'effective';
              return `<div style="background:rgba(255,100,0,0.15);border-top:1px solid rgba(255,100,0,0.3);padding:4px 8px;font-size:9px;color:#ffbb77;text-align:center;">
                ${label}: <strong style="color:#ffdd99;font-size:11px;">${withTarget}</strong> dmg (${tags.join(', ')})
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
  // Show MISS! popup for enemy misses only (player misses are per-hit via replayHits)
  if (combat._lastMiss === 'enemy') {
    showMissFloat('combat-player-zone');
    combat._lastMiss = null;
  } else if (combat._lastMiss) {
    combat._lastMiss = null;
  }

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

// Show MISS! floating text anchored to a DOM element (or centered if not found)
function showMissFloat(elementId) {
  const el = elementId ? document.getElementById(elementId) : null;
  const f = document.createElement('div');
  if (el) {
    const rect = el.getBoundingClientRect();
    f.style.cssText = `
      position:fixed;
      left:${rect.left + rect.width / 2}px;
      top:${rect.top + rect.height * 0.2}px;
      transform:translateX(-50%);
      color:#fff; font-size:22px; font-weight:bold;
      pointer-events:none; z-index:99999;
      text-shadow:0 1px 6px rgba(0,0,0,0.9), 0 0 10px rgba(255,200,0,0.7);
      animation:floatUp 1.1s ease-out forwards;
    `;
  } else {
    f.style.cssText = `
      position:fixed; left:50%; top:42%; transform:translate(-50%,-50%);
      color:#fff; font-size:22px; font-weight:bold;
      pointer-events:none; z-index:99999;
      text-shadow:0 1px 6px rgba(0,0,0,0.9), 0 0 10px rgba(255,200,0,0.7);
      animation:floatUp 1.1s ease-out forwards;
    `;
  }
  f.textContent = 'MISS!';
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
  const dc   = _getDiceColors(card);
  const bc   = dc.cardBorder;
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
        background:${dc.cardBg};
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
  const hits = (hitLog || []).filter(h => h && (h.dmg > 0 || h.missed));
  if (hits.length === 0) { onDone && onDone(); return; }
  let i = 0;
  function next() {
    if (i >= hits.length) { onDone && onDone(); return; }
    const h = hits[i];
    if (h.missed) {
      showMissFloat(h.targetId ? `enemy-card-${h.targetId}` : null);
    } else {
      showTargetedFloat(h.targetId, h.dmg);
    }
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
  const actionLabel = action === 'discard' ? 'Discard' : action === 'setup' ? 'Setup' : action === 'nightmare' ? 'Choose' : action === 'topdraw' ? 'Top of Draw' : action === 'upgrade' ? 'Upgrade' : action === 'copy' ? 'Copy' : action === 'retain' ? 'Retain' : action === 'tohand' ? 'Take to Hand' : 'Exhaust';
  const actionColor = action === 'discard' ? '#f39c12' : action === 'setup' ? '#4fc3f7' : action === 'nightmare' ? '#9b59b6' : action === 'topdraw' ? '#2ecc71' : action === 'upgrade' ? '#3498db' : action === 'copy' ? '#e67e22' : action === 'retain' ? '#2ecc71' : action === 'tohand' ? '#4fc3f7' : '#7f8c8d';

  const pileMap = {
    hand:    { cards: combat.hand || [],        label: 'Hand'         },
    draw:    { cards: combat.drawPile || [],    label: 'Draw Pile'    },
    discard: { cards: combat.discardPile || [], label: 'Discard Pile' },
    exhaust: { cards: combat.exhaustPile || [], label: 'Exhaust Pile' },
  };
  let { cards: pileCards, label: pileLabel } = pileMap[pile] || pileMap.hand;

  // Nightmare: if hand is empty, show all cards across hand+draw+discard (unique by name)
  if (action === 'nightmare' && pileCards.length === 0) {
    const allCards = [...(combat.hand || []), ...(combat.drawPile || []), ...(combat.discardPile || [])];
    const seen = new Set();
    pileCards = allCards.filter(c => { if (seen.has(c.name)) return false; seen.add(c.name); return true; });
    pileLabel = 'Deck';
  }

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
        ${action === 'retain' ? `Well-Laid Plans` : `${actionLabel} ${count} Card${count !== 1 ? 's' : ''}`}
      </h2>
      <p style="color:#aaa; text-align:center; margin:0 0 14px; font-size:12px;">
        ${action === 'retain' ? `Choose up to ${count} card${count !== 1 ? 's' : ''} to keep in your hand next turn.` : action === 'nightmare' ? `Choose a card to conjure ${options._nightmareCount || 3} copies of next turn.` : action === 'topdraw' ? `Choose a card to place on top of your Draw Pile.` : action === 'upgrade' ? `Choose a card to upgrade for the rest of combat.` : action === 'copy' ? `Choose an Attack or Power card to conjure ${options._copyCount || 1} cop${(options._copyCount || 1) !== 1 ? 'ies' : 'y'} of to Hand.` : action === 'tohand' ? `Choose ${count} card${count !== 1 ? 's' : ''} from your ${pileLabel} to take into your Hand.` : `Choose ${count} card${count !== 1 ? 's' : ''} from your ${pileLabel} to ${actionLabel.toLowerCase()}.`}
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
    countLabel.textContent = action === 'retain'
      ? `Selected: ${selected.size} / up to ${count}`
      : `Selected: ${selected.size} / ${count}`;
    const ready = action === 'retain' ? true : selected.size === count;
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
    if (action !== 'retain' && selected.size !== count) return;

    if (action === 'retain') {
      // Well-Laid Plans: mark selected cards for retain (0–N allowed)
      for (const idx of selected) {
        pileCards[idx]._retain = true;
        window.CombatEngine && window.CombatEngine.addLog(`Well-Laid Plans: ${pileCards[idx].name} retained`, 'success');
      }
    } else if (action === 'nightmare') {
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
    } else if (action === 'tohand') {
      // Hologram / Seek: move selected cards from source pile directly into hand
      const sortedIdx = [...selected].sort((a, b) => b - a);
      for (const idx of sortedIdx) {
        const card = pileCards.splice(idx, 1)[0];
        combat.hand.push(card);
        window.CombatEngine && window.CombatEngine.addLog(`${card.name} → Hand`, 'info');
      }
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
      // Burning Pact: draw deferred cards now that exhaust is resolved
      if (options.drawAfter && options.drawAfter > 0 && window.CombatEngine && window.CombatEngine.drawCards) {
        window.CombatEngine.drawCards(options.drawAfter);
      }
    }

    overlay.remove();
    updateCombatDisplay();
    checkCombatEnd();

    // Chain pending retain picker (e.g. both Tools of the Trade and Well-Laid Plans active)
    if (action !== 'retain' && combat._pendingRetainPick) {
      const rp = combat._pendingRetainPick;
      combat._pendingRetainPick = null;
      setTimeout(() => window.showCardPickerModal({ action: 'retain', pile: 'hand', count: rp.count }), 80);
    }
  });
};

// ============== STUBS ==============

function cleanup3DDice() {}

// ============================================================
// ============== DICE CARD PLAY FLOW ==========================
// ============================================================

/**
 * Called instead of normal play when a Dice-type card is clicked.
 * All dice go straight to the board — no popup.
 * Isaac's D6 transform is applied when the tile is clicked.
 */
function handleDiceCardPlay(diceCardIndex, combat) {
  const hand     = combat.hand || [];
  const diceCard = hand[diceCardIndex];
  if (!diceCard) return;

  window.CombatEngine.playCard(diceCardIndex, null);
  const diceDef   = (typeof DICE_DATA !== 'undefined') ? DICE_DATA.find(d => d.name === diceCard.name) : null;
  const sides     = diceDef ? diceDef.faces.length : 6;
  const faceIndex = Math.floor(Math.random() * sides);
  if (window.CombatEngine && window.CombatEngine.addPendingDie) {
    window.CombatEngine.addPendingDie(diceCard.name, faceIndex);
  }
  updateCombatDisplay();
}

/**
 * Show card-picker for Isaac's D6 after the player clicks its pending tile.
 * The die was already rolled and animated; we just need the player to choose
 * which hand card to transform, then apply the effect and consume the pending entry.
 */
function _showIsaacTransformPicker(face, combat, pendingId) {
  const pickable = (combat.hand || []).map((c, i) => ({ card: c, handIdx: i }));

  if (pickable.length === 0) {
    // Nothing to transform — just consume the pending entry
    if (pendingId && window.CombatEngine) {
      combat.pendingDice = (combat.pendingDice || []).filter(e => e.id !== pendingId);
    }
    updateCombatDisplay();
    return;
  }

  const combatModal = document.getElementById('dice-combat-modal');
  if (!combatModal) return;
  combatModal.style.position = 'relative';

  const overlay = document.createElement('div');
  overlay.id = 'dice-card-pick-overlay';
  overlay.style.cssText = `position:absolute;inset:0;z-index:999;background:rgba(0,0,0,0.88);
    display:flex;align-items:center;justify-content:center;border-radius:inherit;`;

  overlay.innerHTML = `
    <div style="background:#1a1208;border:2px solid #cc8800;border-radius:12px;padding:20px;
      max-width:700px;width:92%;text-align:center;">
      <h2 style="color:#f0c850;margin:0 0 6px;font-size:18px;">🎲 Isaac's D6</h2>
      <p style="color:#aaa;margin:0 0 14px;font-size:12px;">Choose a card to transform</p>
      <div id="dice-pick-cards" style="display:flex;gap:10px;flex-wrap:wrap;justify-content:center;
        max-height:45vh;overflow-y:auto;padding:4px;">
        ${pickable.map(({ card: c, handIdx }) => {
          const bc = typeColor(c.type);
          const bg = cardTypeBg(c.type);
          const imgSrc = c.imageUrl || '';
          return `<div class="dice-pick-card" data-hand-idx="${handIdx}"
            style="background:${bg};border:2px solid ${bc};border-radius:8px;padding:8px;
              cursor:pointer;min-width:90px;max-width:110px;text-align:center;
              transition:transform 0.1s,box-shadow 0.1s;"
            onmouseover="this.style.transform='translateY(-4px)';this.style.boxShadow='0 8px 20px rgba(0,0,0,0.6)'"
            onmouseout="this.style.transform='';this.style.boxShadow=''">
            <div style="width:100%;height:50px;display:flex;align-items:center;justify-content:center;
              background:rgba(0,0,0,0.3);border-radius:5px;margin-bottom:5px;overflow:hidden;">
              ${imgSrc
                ? `<img src="${imgSrc}" style="width:100%;height:100%;object-fit:contain;padding:2px;box-sizing:border-box;"
                     onerror="if(this.dataset.t){this.style.display='none';this.parentElement.innerHTML='<span style=font-size:26px>${typeEmoji(c.type)}</span>';}else{this.dataset.t=1;this.src='images/heroes/${c.name}.png';}">`
                : `<span style="font-size:26px;">${typeEmoji(c.type)}</span>`}
            </div>
            <div style="font-size:10px;font-weight:bold;color:#fff;">${c.name}${c.upgraded ? '<span style="color:#4CAF50">+</span>' : ''}</div>
            <div style="font-size:9px;color:#aaa;margin-top:2px;">${c.type}</div>
          </div>`;
        }).join('')}
      </div>
      <p style="color:#555;font-size:10px;margin:10px 0 0;">Click a card to transform it</p>
    </div>`;

  combatModal.appendChild(overlay);

  overlay.querySelectorAll('.dice-pick-card').forEach(el => {
    el.addEventListener('click', () => {
      const pickedHandIdx = parseInt(el.dataset.handIdx);
      const pickedCard    = combat.hand[pickedHandIdx];
      overlay.remove();

      // Consume the pending die entry
      if (pendingId) {
        combat.pendingDice = (combat.pendingDice || []).filter(e => e.id !== pendingId);
      }

      // Apply the transform effect directly (die was already rolled + animated)
      _applyDiceRollEffect({ name: "Isaac's D6" }, pickedCard, pickedHandIdx, face);
    });
  });
}

/**
 * Show the 3D die rolling, then apply the transform effect to pickedCard.
 */
function _showDiceRollOverlay(diceCard, pickedCard, newPickIdx) {
  const diceDef = (typeof DICE_DATA !== 'undefined' ? DICE_DATA : []).find(d => d.name === diceCard.name);
  const sides   = diceDef ? diceDef.faces.length : 6;

  const combatModal = document.getElementById('dice-combat-modal');

  if (!combatModal || typeof DiceRendererInstance === 'undefined') {
    const rolledN  = Math.floor(Math.random() * sides) + 1;
    const faceData = diceDef ? (diceDef.faces.find(f => f.face === rolledN) || diceDef.faces[0])
                             : { face: rolledN, text: String(rolledN) };
    _applyDiceRollEffect(diceCard, pickedCard, newPickIdx, faceData);
    return;
  }

  const overlay = document.createElement('div');
  overlay.id = 'dice-roll-overlay';
  overlay.style.cssText = `position:absolute;inset:0;z-index:1000;background:rgba(0,0,0,0.9);
    display:flex;flex-direction:column;align-items:center;justify-content:center;border-radius:inherit;`;

  overlay.innerHTML = `
    <h2 style="color:#f0c850;margin:0 0 12px;font-size:20px;">🎲 Rolling ${diceCard.name}…</h2>
    <div id="dice-roll-3d" style="width:160px;height:160px;margin:0 auto;"></div>
    <div id="dice-roll-label" style="color:#fff;font-size:15px;min-height:52px;margin-top:14px;text-align:center;"></div>
    <div id="dice-roll-btns" style="margin-top:16px;display:flex;gap:10px;"></div>`;

  combatModal.style.position = 'relative';
  combatModal.appendChild(overlay);

  requestAnimationFrame(() => {
    const container = document.getElementById('dice-roll-3d');
    if (!container) { overlay.remove(); _applyDiceRollEffect(diceCard, pickedCard, newPickIdx, { face: 1, text: '' }); return; }

    const renderer   = new DiceRendererInstance();
    const diceData3d = _makeDiceDataForCard(diceCard);
    renderer.init(container, diceData3d.colors ? diceData3d.colors.sceneBg : 0x0d0800);
    renderer.createDice(diceData3d);

    const performRoll = (rolledN) => {
      const faceData = diceDef ? (diceDef.faces.find(f => f.face === rolledN) || diceDef.faces[0])
                               : { face: rolledN, text: String(rolledN) };
      const lbl  = document.getElementById('dice-roll-label');
      const btns = document.getElementById('dice-roll-btns');
      if (lbl)  lbl.innerHTML = '';
      if (btns) btns.innerHTML = '';

      renderer.rollDice(diceData3d, rolledN, () => {
        if (lbl) lbl.innerHTML =
          `<div style="color:#f0c850;font-weight:bold;font-size:18px;">${faceData.text}</div>
           <div style="color:#888;font-size:11px;margin-top:4px;">Face ${rolledN}</div>`;

        const finish = () => {
          renderer.dispose();
          overlay.remove();
          _applyDiceRollEffect(diceCard, pickedCard, newPickIdx, faceData);
        };

        if (btns) {
          const continueBtn = document.createElement('button');
          continueBtn.textContent = 'Continue →';
          continueBtn.style.cssText = `padding:8px 20px;background:#2a5c2a;border:1px solid #4a9c4a;
            color:#fff;border-radius:6px;font-size:14px;cursor:pointer;`;
          continueBtn.onclick = finish;
          btns.appendChild(continueBtn);
        }
      });
    };

    performRoll(Math.floor(Math.random() * sides) + 1);
  });
}

/**
 * Applies the transformation: replace pickedCard in hand with a random card of the rolled type.
 */
function _applyDiceRollEffect(diceCard, pickedCard, newPickIdx, faceData) {
  const combat   = window.CombatEngine && window.CombatEngine.getCombatState();
  if (!combat) return;

  const faceText = (faceData.text || '').toLowerCase();
  let types  = [];
  let makeFree = false;

  if      (faceText.includes('curse'))  types = ['curse'];
  else if (faceText.includes('status')) types = ['status'];
  else if (faceText.includes('skill'))  types = ['skill'];
  else if (faceText.includes('power'))  types = ['power'];
  else if (faceText.includes('attack')) types = ['attack'];
  if (faceText.includes('free'))        makeFree = true;
  // Face 6: "Random Attack, Skill, or Power that is free..."
  if (makeFree && types.length === 1 && types[0] === 'attack') types = ['attack', 'skill', 'power'];

  const allCards = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA : [];
  const pool = allCards.filter(c =>
    types.length === 0 || types.includes((c.type || '').toLowerCase())
  );

  // Find the target slot — first try stored index, then search by reference
  let targetIdx = newPickIdx;
  if (targetIdx < 0 || targetIdx >= combat.hand.length || combat.hand[targetIdx] !== pickedCard) {
    targetIdx = combat.hand.indexOf(pickedCard);
  }

  if (pool.length > 0 && targetIdx >= 0) {
    const newCard = { ...pool[Math.floor(Math.random() * pool.length)] };
    if (makeFree) newCard.cost = 0;
    const oldName = pickedCard.name;
    combat.hand[targetIdx] = newCard;

    const freeStr = makeFree ? ' (free this combat!)' : '';
    if (combat.log) combat.log.push({
      text: `${diceCard.name}: ${oldName} → ${newCard.name}${freeStr}`,
      type: 'info'
    });
    if (typeof createNotification === 'function') {
      createNotification(`${oldName} → ${newCard.name}${freeStr}`, '#f0c850', '🎲');
    }
  }

  updateCombatDisplay();
  checkCombatEnd();
}

// ============================================================
// ============== S&D DICE ROLL → PENDING PANEL ================
// ============================================================

/**
 * Show 3D die rolling animation for an S&D dice card,
 * then add the result to the pending dice panel.
 */
function _showDiceRollAndPend(diceCard, combat) {
  const diceDef = (typeof DICE_DATA !== 'undefined' ? DICE_DATA : []).find(d => d.name === diceCard.name);
  const sides   = diceDef ? diceDef.faces.length : 6;

  const combatModal = document.getElementById('dice-combat-modal');

  const commitFace = (faceIndex) => {
    if (window.CombatEngine && window.CombatEngine.addPendingDie) {
      window.CombatEngine.addPendingDie(diceCard.name, faceIndex);
    }
    // Upgraded die: grant +1 Reroll when played
    if (diceCard.upgraded && window.CombatEngine) {
      const cs = window.CombatEngine.getCombatState();
      if (cs) {
        cs.player.rerolls = (cs.player.rerolls || 0) + 1;
        if (typeof window !== 'undefined') window.reroll = cs.player.rerolls;
        window.CombatEngine.addLog(`${diceCard.name}+: +1 Reroll`, 'info');
      }
    }
    updateCombatDisplay();
    checkCombatEnd();
  };

  if (!combatModal || typeof DiceRendererInstance === 'undefined') {
    const faceIndex = Math.floor(Math.random() * sides);
    commitFace(faceIndex);
    return;
  }

  const overlay = document.createElement('div');
  overlay.id = 'dice-roll-overlay';
  overlay.style.cssText = `position:absolute;inset:0;z-index:1000;background:rgba(0,0,0,0.9);
    display:flex;flex-direction:column;align-items:center;justify-content:center;border-radius:inherit;`;

  overlay.innerHTML = `
    <h2 style="color:#f0c850;margin:0 0 12px;font-size:20px;">🎲 Rolling ${diceCard.name}…</h2>
    <div id="dice-roll-3d" style="width:160px;height:160px;margin:0 auto;"></div>
    <div id="dice-roll-label" style="color:#fff;font-size:15px;min-height:52px;margin-top:14px;text-align:center;"></div>
    <div id="dice-roll-btns" style="margin-top:16px;display:flex;gap:10px;"></div>`;

  combatModal.style.position = 'relative';
  combatModal.appendChild(overlay);

  requestAnimationFrame(() => {
    const container = document.getElementById('dice-roll-3d');
    if (!container) {
      overlay.remove();
      commitFace(Math.floor(Math.random() * sides));
      return;
    }

    const renderer   = new DiceRendererInstance();
    const diceData3d = _makeDiceDataForCard(diceCard);
    renderer.init(container, diceData3d.colors ? diceData3d.colors.sceneBg : 0x0d0800);
    renderer.createDice(diceData3d);

    const performRoll = (faceIndex) => {
      const rolledN  = faceIndex + 1; // face numbers are 1-based
      const faceData = diceDef ? (diceDef.faces[faceIndex] || diceDef.faces[0]) : { face: rolledN, text: String(rolledN) };
      const lbl  = document.getElementById('dice-roll-label');
      const btns = document.getElementById('dice-roll-btns');
      if (lbl)  lbl.innerHTML = '';
      if (btns) btns.innerHTML = '';

      renderer.rollDice(diceData3d, rolledN, () => {
        const faceLabel = faceData.isBlank ? '— (blank)' : faceData.text;
        if (lbl) lbl.innerHTML =
          `<div style="color:#f0c850;font-weight:bold;font-size:18px;">${faceLabel}</div>
           <div style="color:#888;font-size:11px;margin-top:4px;">Face ${rolledN}
             ${faceData.addons && faceData.addons.length > 0 ? '· ' + faceData.addons.join(', ') : ''}
           </div>`;

        const finish = () => {
          renderer.dispose();
          overlay.remove();
          commitFace(faceIndex);
        };

        if (btns) {
          const continueBtn = document.createElement('button');
          continueBtn.textContent = 'Add to Panel →';
          continueBtn.style.cssText = `padding:8px 20px;background:#2a5c2a;border:1px solid #4a9c4a;
            color:#fff;border-radius:6px;font-size:14px;cursor:pointer;`;
          continueBtn.onclick = finish;
          btns.appendChild(continueBtn);
        }
      });
    };

    performRoll(Math.floor(Math.random() * sides));
  });
}

// ============================================================
// ============== PENDING DICE PANEL ===========================
// ============================================================

/**
 * Return display text for a pending die face, applying stat bonuses to damage values
 * and showing persistence bonus on status effects.
 */
function getDiceFaceDynamicText(face, combat) {
  if (!face || !face.text || face.isBlank) return face ? (face.text || '—') : '—';
  if (!combat || !combat.player) return face.text;

  const effects = face.effects || [];
  const player  = combat.player;
  let text = face.text;

  // Damage boost from power / weak / flat melee bonus (Focus Crystal)
  const hasDmg = effects.some(e => e.move === 'dmg');
  if (hasDmg) {
    const power = player.statuses['power'] || 0;
    const weak  = player.statuses['weak'] ? 0.75 : 1;
    const hasMeleeEffect = effects.some(e => e.move === 'dmg' && (e.addons || []).some(a => a.toLowerCase() === 'melee'));
    const flatBonus = (hasMeleeEffect && combat._flatAttackBonus) ? combat._flatAttackBonus : 0;
    text = text.replace(/(\d+) Dmg/gi, (_, n) => {
      const base    = parseInt(n);
      const boosted = Math.max(0, Math.floor((base + power + flatBonus) * weak));
      if (boosted === base) return `${base} Dmg`;
      const col = boosted > base ? '#7dff7d' : '#ff7d7d';
      return `<span style="color:${col};font-weight:bold">${boosted}</span> Dmg`;
    });
  }

  // Persistence bonus on `get` (player self-buff) status effects
  const persistence = player.statuses['persistence'] || 0;
  if (persistence > 0) {
    const getEffect = effects.find(e => e.move === 'get' && e.statusKey);
    if (getEffect) {
      const exempt = new Set(['power', 'defense', 'arcane', 'persistence']);
      const key = getEffect.statusKey.toLowerCase();
      if (!exempt.has(key)) {
        const statusDef = typeof STATUSES_DATA !== 'undefined' ? STATUSES_DATA[key] : null;
        if (statusDef && (statusDef.type === 'Buff' || statusDef.type === 'Debuff')) {
          const base = getEffect.value || 0;
          const total = base + persistence;
          text = text.replace(new RegExp(`\\b${base}\\b`), `<span style="color:#c09aff;font-weight:bold">${total}</span>`);
        }
      }
    }
  }

  return text;
}

/**
 * Render the pending dice strip between the player zone and hand.
 * Shows one tile per pending die entry. Cantrip tiles show that they already fired.
 */
function renderPendingDicePanel(combat) {
  const pending = (combat && combat.pendingDice) || [];

  // Show whenever the player has a dice card anywhere in their deck
  const isDieCard = c => (c.type || '').toLowerCase() === 'dice';
  const hasDiceInDeck = (combat && (
    (combat.hand        || []).some(isDieCard) ||
    (combat.drawPile    || []).some(isDieCard) ||
    (combat.discardPile || []).some(isDieCard) ||
    (combat.exhaustPile || []).some(isDieCard)
  ));

  if (pending.length === 0 && !hasDiceInDeck) return '';

  const rerolls = (combat.player && combat.player.rerolls) || 0;
  const gold   = C.gold   || '#f0c850';
  const border = C.border || 'rgba(255,255,255,0.15)';

  const tilesHtml = pending.map(entry => {
    const face = entry.face || {};
    const isBlank = face.isBlank;
    const addons  = face.addons || [];
    const isCantrip   = addons.includes('cantrip');
    const isSingleUse = addons.includes('singleUse');
    const isDruid     = addons.includes('druid');
    const needsTarget = !isBlank && (face.effects || []).some(e => /^(dmg|magic_dmg|magic dmg)$/i.test(e.move || '') && !(e.addons || []).some(a => a.toLowerCase() === 'cleave'));

    const isSelected = window._selectedPendingId === entry.id;

    // Use the die's own color scheme for the tile border
    const srcCard = typeof CARDS_DATA !== 'undefined' ? CARDS_DATA.find(c => c.name === entry.cardName) : null;
    const dieColors = srcCard ? _getDiceColors(srcCard) : null;
    const tagBorderColor = dieColors ? dieColors.cardBorder : null;

    const addonBadges = [
      isCantrip   ? `<span style="font-size:8px;background:#4a2c8a;color:#c09aff;border-radius:3px;padding:0 3px;">Cantrip</span>` : '',
      isSingleUse ? `<span style="font-size:8px;background:#8a2c2c;color:#ffaaaa;border-radius:3px;padding:0 3px;">1-Use</span>` : '',
      isDruid     ? `<span style="font-size:8px;background:#2c5a2c;color:#aaffaa;border-radius:3px;padding:0 3px;">Druid</span>` : '',
      needsTarget ? `<span style="font-size:8px;background:#5a3a00;color:#ffcc44;border-radius:3px;padding:0 3px;">Target</span>` : ''
    ].filter(Boolean).join(' ');

    const selectedGlow = isSelected ? `box-shadow:0 0 16px ${gold}aa;` : '';

    return `<div class="pending-die-tile" data-pending-id="${entry.id}"
      style="
        padding:4px 6px;
        background:transparent;
        border-radius:8px; cursor:${isBlank ? 'default' : 'pointer'};
        display:flex; flex-direction:column; align-items:center; gap:2px;
        ${selectedGlow}
        transition:box-shadow 0.1s;
      ">
      <div style="font-size:9px;color:#aaa;line-height:1;">${entry.cardName}</div>
      <div class="pending-dice-3d"
        data-pending-id="${entry.id}"
        data-face-num="${entry.faceIndex + 1}"
        data-card-name="${entry.cardName}"
        style="width:90px;height:90px;pointer-events:none;flex-shrink:0;">
      </div>
      <div style="font-size:10px;color:${isBlank ? '#666' : '#ddd'};text-align:center;line-height:1.2;max-width:110px;">
        ${getDiceFaceDynamicText(face, combat)}
      </div>
      <div style="display:flex;gap:2px;flex-wrap:wrap;justify-content:center;">
        ${addonBadges}
      </div>
    </div>`;
  }).join('');

  const emptyHint = pending.length === 0 ? `
    <div id="dice-drop-hint" style="
      grid-column:1/-1; display:flex; align-items:center; justify-content:center;
      color:#555; font-size:12px; font-style:italic; pointer-events:none;
      padding:8px 0; min-height:36px;
    ">drag a die card here to roll it</div>` : '';

  return `
    <div id="pending-dice-panel" style="
      flex-shrink:0; padding:6px 10px 8px;
      background:rgba(0,0,0,0.4);
      border-top:1px solid ${border};
      transition:background 0.15s, border-color 0.15s;
    ">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px;">
        <div style="font-size:11px;font-weight:bold;color:${gold};">🎲 Dice Board</div>
        ${rerolls > 0 ? `
          <button id="pending-reroll-all-btn" style="
            padding:3px 9px;
            background:#5c3a0a; border:1px solid #c07820;
            color:${gold}; border-radius:6px; font-size:10px; cursor:pointer;
          ">🔄 Reroll All (${rerolls})</button>
        ` : `
          <div style="font-size:10px;color:#666;">No rerolls</div>
        `}
      </div>
      <div id="dice-board-drop-zone" style="
        display:grid;
        grid-template-columns:repeat(auto-fill,minmax(100px,1fr));
        gap:6px;
        min-height:36px;
      ">
        ${tilesHtml}${emptyHint}
      </div>
    </div>
  `;
}

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

// Spellbook tab: cast a spell by name (or enter targeting mode for single-target damage spells)
window._handleSpellbookCast = function(spellName) {
  const cs = window.CombatEngine && window.CombatEngine.getCombatState();
  if (!cs || cs.phase !== 'player_action') return;

  // Toggle off if this spell is already pending targeting
  if (window._pendingSpellName === spellName) {
    window._pendingSpellName = null;
    updateCombatDisplay();
    return;
  }

  const spell = (cs.spells || []).find(s => s.name === spellName);
  if (!spell) return;

  if (window.CombatEngine.spellNeedsTarget && window.CombatEngine.spellNeedsTarget(spell)) {
    window._pendingSpellName = spellName;
    updateCombatDisplay();
    return;
  }

  if (!window.CombatEngine.castSpell) return;
  const result = window.CombatEngine.castSpell(spellName, {});
  if (result && !result.success && result.error) {
    typeof createNotification === 'function' &&
      createNotification(result.error, '#e74c3c', '✨');
  }
  updateCombatDisplay();
  checkCombatEnd();
};

window.cancelCombatDrag = function() {
  if (_dragState) {
    if (_dragState.clone)  _dragState.clone.remove();
    if (_dragState.cardEl) _dragState.cardEl.style.opacity = '';
    _dragState = null;
  }
  const combat = window.CombatEngine && window.CombatEngine.getCombatState();
  if (combat && combat.selectedCardIndex !== null && combat.selectedCardIndex !== undefined) {
    combat.selectedCardIndex = null;
  }
};


// Phase 5: window-exports added for ESM transition (functions/vars called cross-file).
window.C = C;
window._makeDiceDataForCard = _makeDiceDataForCard;
window.checkCombatEnd = checkCombatEnd;
window.cleanup3DDice = cleanup3DDice;
window.hideStatusTooltip = hideStatusTooltip;
window.rarityColor = rarityColor;
window.renderCombatUI = renderCombatUI;
window.typeColor = typeColor;
window.typeEmoji = typeEmoji;
window.updateCombatDisplay = updateCombatDisplay;
window.updateItemsBar = updateItemsBar;
