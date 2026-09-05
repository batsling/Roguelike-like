/* THE OBS COMPANION OVERLAY — the ticker (docs/games-first-redesign.md §9).
 *
 * INSTALLED, NOT AUTHORED IN PLACE: the game overwrites user://obs/overlay.js
 * from res://obs/overlay.js at every boot. Edit the repo's copy.
 *
 * HOW THE STATE GETS HERE, and why it is not fetch(). OBS renders this page from
 * a file:// URL, and Chromium refuses every fetch()/XHR a file:// page makes at
 * a sibling file — there is no origin to grant, so it is a CORS failure with no
 * way round it short of launching OBS with --allow-file-access-from-files, which
 * is not something a setup guide should ask for. A <script> tag has no such
 * restriction: a file:// page may always load a sibling script. So the game
 * writes its state AS a script — `window.OBS_STATE = {...}` — and this file
 * re-loads it on a timer with a cache-buster on the end.
 *
 * That is the whole transport. No server, no port, no websocket. */

'use strict';

/* The payload shape this page knows how to draw (ObsCompanion.PAYLOAD_VERSION).
 * A newer payload is refused rather than half-drawn: an overlay that quietly
 * shows the wrong health is worse than one that says it is out of date. */
const KNOWN_VERSION = 1;

const POLL_MS = 250;
/* Longer than ObsCompanion's five-second heartbeat, with room for a slow frame.
 * Below this the game is alive and simply has nothing new to say. */
const STALE_MS = 20000;
const TOAST_MS = 6000;

const el = (id) => document.getElementById(id);
const overlay = el('overlay');

let lastStamp = null;     /* payload `at` of the last state we drew */
let lastSeenAt = 0;       /* wall-clock ms when that arrived */
let firstDraw = true;
let shownEvents = new Set();
let doneRows = new Set();
let goalSignature = '';

/* ----------------------------------------------------------- the polling -- */

function poll() {
  const s = document.createElement('script');
  /* Chromium strips the query when it resolves a file:// path but still keys its
   * cache on the whole URL, which is exactly the behaviour this needs. */
  s.src = 'state.js?t=' + Date.now();
  s.onload = () => { s.remove(); consume(); };
  s.onerror = () => { s.remove(); };
  document.head.appendChild(s);
}

function consume() {
  const state = window.OBS_STATE;
  if (!state) return;
  if (state.v > KNOWN_VERSION) {
    el('offline').textContent =
      'This overlay page is older than the game — reinstall it from the settings screen.';
    overlay.classList.add('waiting');
    return;
  }
  if (state.at === lastStamp) return;   /* the heartbeat has not ticked */
  lastStamp = state.at;
  lastSeenAt = Date.now();
  render(state);
}

/* The overlay dims when the heartbeat stops, and comes back on its own if the
 * game is restarted — there is nothing to reset in OBS. */
function checkStale() {
  const stale = lastSeenAt > 0 && (Date.now() - lastSeenAt) > STALE_MS;
  overlay.classList.toggle('stale', stale);
}

/* ---------------------------------------------------------- the drawing --- */

function render(s) {
  overlay.classList.toggle('waiting', s.state === 'idle');
  drawVerdict(s.state);
  drawEvents(s.events || []);
  if (s.state === 'idle') { firstDraw = false; return; }

  drawHero(s.hero || {}, s.vitals || {}, s.board || {});
  drawBarThreat(s.vitals || {}, s.threat || {});
  drawCost(s.threat || {}, s.art || {}, s.now || {});
  drawShields(s.vitals || {}, s.art || {});
  drawNow(s.now || {}, s.run || {});
  drawGoals(s.goals || []);
  drawStatuses(s.statuses || [], s.art || {});
  drawRoad(s.road || []);
  firstDraw = false;
}

/* ONE SPRITE PER SHIELD, in the board's order: the pool that stays comes first
 * and bare, the timed ones follow wearing the clock. Position and badge say the
 * same thing twice — the further from the portrait a shield is, the sooner it
 * goes — which is what makes the row readable with no tooltip to hover. */
function drawShields(vitals, art) {
  const box = el('hero-shields');
  box.innerHTML = '';
  el('shield-row').hidden = num(vitals.shields) === 0;
  if (!art || !art.shield) return;
  const rows = [[num(vitals.shields_kept), false], [num(vitals.shields_timed), true]];
  for (const [count, timed] of rows) {
    for (let i = 0; i < count; i++) {
      const s = document.createElement('span');
      s.className = 'shield-pip';
      s.title = timed ? 'Temporary shield — goes when you report this game'
                      : 'Shield — nothing takes it but a hit';
      const img = document.createElement('img');
      img.alt = 'shield';
      img.src = art.shield;
      s.appendChild(img);
      if (timed && art.timer) {
        const clock = document.createElement('img');
        clock.className = 'pip-clock';
        clock.alt = '';
        clock.src = art.timer;
        s.appendChild(clock);
      }
      box.appendChild(s);
    }
  }
}

/* WHAT A LOST RUN COSTS, one mark per swing, in the order the board resolves
 * them: a blocked swing wears the shield that breaks on it, an unblocked one
 * shows the damage it lands. Read left to right the row IS the rule — shields
 * eat whole hits, and everything past your last shield is Health. */
function drawCost(threat, art, now) {
  const box = el('cost');
  const swings = (threat && threat.swings) || [];

  /* WHICH attempt this would be — `now.attempts` counts the ones already spent,
   * so the one this line is forecasting is the next one up. It sits under the
   * label rather than in the Now Playing card, where it was a chip a long way
   * from the consequence it belongs to. */
  const att = el('cost-attempt');
  const spent = num(now && now.attempts);
  att.hidden = false;
  att.textContent = 'Attempt ' + (spent + 1);
  att.title = spent === 0 ? 'no runs lost at this game yet'
    : spent + (spent === 1 ? ' run lost here so far' : ' runs lost here so far');
  /* Nothing that can reach you: the line goes entirely rather than announcing a
   * threat of zero, which reads as a threat. */
  box.hidden = swings.length === 0;
  if (box.hidden) return;

  const strip = el('cost-swings');
  strip.innerHTML = '';
  for (const sw of swings) {
    const s = document.createElement('span');
    s.className = 'swing ' + (sw.blocked ? 'blocked' : 'hits');
    s.title = sw.who + ' swings for ' + sw.damage
      + (sw.blocked ? ' — a shield stops it whole' : '');

    /* THE BODY DOING THE SWINGING, as its own face. A row of bare numbers said
     * how much but never who, and "who" is half of what the player is deciding
     * about — the boss's swing and the fly's are not the same problem. */
    if (sw.icon) {
      const img = document.createElement('img');
      img.className = 'swing-art';
      img.alt = sw.who;
      img.src = sw.icon;
      s.appendChild(img);
    } else {
      /* No art for this body: fall back to the bare number, which is what the
       * row used to be all the way across. */
      const n = document.createElement('span');
      n.className = 'swing-bare';
      n.textContent = sw.damage;
      s.appendChild(n);
    }

    /* The badge in the corner is the binary: a shield means this swing is eaten
     * whole, a number means that much Health. Greyed art behind the shield says
     * the same thing a second way. */
    const badge = document.createElement('span');
    if (sw.blocked && art && art.shield) {
      badge.className = 'swing-badge shield';
      const sh = document.createElement('img');
      sh.alt = 'blocked';
      sh.src = art.shield;
      badge.appendChild(sh);
    } else if (sw.icon) {
      badge.className = 'swing-badge dmg';
      badge.textContent = sw.damage;
    }
    if (badge.className) s.appendChild(badge);
    strip.appendChild(s);
  }

  const total = el('cost-total');
  const dmg = num(threat.damage);
  const broke = num(threat.blocked);
  /* The sentence under the marks, for the viewer who wants it stated rather
   * than counted. */
  const parts = [];
  if (broke > 0) parts.push(broke + (broke === 1 ? ' shield' : ' shields'));
  parts.push(dmg + ' damage');
  total.textContent = '= ' + parts.join(', ');
  total.className = 'cost-total' + (dmg === 0 ? ' safe' : '');

  /* THE ONE STATE ALLOWED TO SHOUT. A hatched bar covering the whole of a short
   * health total does say "all of it goes", but only to someone already reading
   * the bar — and this is the moment the overlay exists for. */
  const kill = el('cost-lethal');
  kill.hidden = !threat.lethal;
  box.classList.toggle('lethal', !!threat.lethal);
}

/* The same forecast on the bar: a hatched notch covering the Health that would
 * go, parked at the leading edge of the fill. */
function drawBarThreat(vitals, threat) {
  const node = el('hp-threat');
  const max = Math.max(1, num(vitals.max));
  const hp = num(vitals.hp);
  const dmg = Math.min(hp, num(threat && threat.damage));
  node.hidden = dmg <= 0;
  if (node.hidden) return;
  const pct = (v) => Math.max(0, Math.min(100, (v / max) * 100));
  node.style.left = pct(hp - dmg) + '%';
  node.style.width = (pct(hp) - pct(hp - dmg)) + '%';
  node.classList.toggle('lethal', !!(threat && threat.lethal));
}

function drawHero(hero, vitals, board) {
  setImg(el('hero-icon'), hero.icon);
  el('hero-name').textContent = hero.name || '';
  const lvl = el('hero-level');
  lvl.textContent = hero.level > 1 ? ('Level ' + hero.level) : '';
  lvl.hidden = !(hero.level > 1);

  const hp = num(vitals.hp), max = Math.max(1, num(vitals.max));
  const bar = el('hp-fill').parentElement;
  el('hp-fill').style.width = Math.max(0, Math.min(100, (hp / max) * 100)) + '%';
  el('hp-text').textContent = hp + ' / ' + max;
  bar.classList.toggle('low', hp > 0 && hp / max <= 0.3);

  /* WORDS, NOT SYMBOLS. The game's own UI can lean on ⚔ and ⛨ because it ships
   * the subsetted Noto fonts that carry them; this page is rendered by OBS's
   * Chromium against whatever the host has installed, and a glyph that is
   * missing there comes out as a tofu box or the wrong symbol entirely. */
  /* The threat is drawn by drawCost below, swing by swing, rather than summed
   * into a chip here — see the note in overlay.html. */
  chip(el('bodies'), num(board.bodies) > 0,
    board.bodies + (board.bodies === 1 ? ' body' : ' bodies') + ' following');
}

function drawNow(now, run) {
  setImg(el('now-cover'), now.cover);
  el('now-label').textContent = now.playing ? 'Now playing' : 'Standing on';
  el('now-game').textContent = now.game || '—';
  const hops = num(run.hops, -1);
  chip(el('hops'), hops >= 0,
    hops === 0 ? 'At the Amulet'
      : hops + (hops === 1 ? ' game to the Amulet' : ' games to the Amulet'));
}

function drawGoals(goals) {
  const list = el('goal-list');
  /* Rebuild only when the LIST changed. Redrawing every quarter second would
   * restart the tick-flash animation forever and fight the auto-scroll. */
  const sig = goals.map(g => g.kind + '|' + g.text + '|' + g.done).join('');
  if (sig === goalSignature) return;
  goalSignature = sig;

  const nowDone = new Set(goals.filter(g => g.done).map(g => g.kind + '|' + g.text));
  list.innerHTML = '';
  for (const g of goals) {
    const key = g.kind + '|' + g.text;
    const li = document.createElement('li');
    li.className = 'goal ' + g.kind
      + (g.done ? ' done' : '')
      + (g.front && !g.done ? ' front' : '')
      + (g.boss ? ' boss' : '');
    /* A row that was NOT done a moment ago and is now: flash it, so the tick is
     * something the viewer sees happen. Never on the first draw, where every
     * done row would flash at once. */
    if (g.done && !firstDraw && !doneRows.has(key)) li.classList.add('flash');

    const tick = document.createElement('span');
    tick.className = 'tick';
    tick.textContent = g.done ? '✓' : '□';
    li.appendChild(tick);

    const body = document.createElement('span');
    body.className = 'body';
    const text = document.createElement('span');
    text.className = 'text';
    text.textContent = g.text || '';
    body.appendChild(text);

    const note = subtitle(g);
    if (note) {
      const who = document.createElement('span');
      who.className = 'who';
      who.textContent = note;
      body.appendChild(who);
    }
    li.appendChild(body);
    list.appendChild(li);
  }
  doneRows = nowDone;
  restartScroll('goal-scroll');
}

/* The small grey line under a goal: whose it is, and how long is left on it. */
function subtitle(g) {
  const bits = [];
  if (g.who) bits.push(g.who);
  const games = num(g.games, 0);
  if (g.kind === 'event' || g.kind === 'curse') {
    bits.push(games < 0 ? 'permanent'
      : games + (games === 1 ? ' game left' : ' games left'));
  }
  return bits.join(' · ');
}

/* THE STATUS PIPS, under the portrait — art and a stack count, the same shape
 * BattlefieldView draws under the hero. Written out as names they were words
 * with no picture behind them, which is not something you can read at a glance
 * from across a room. */
function drawStatuses(statuses, art) {
  const box = el('hero-pips');
  box.innerHTML = '';
  el('status-row').hidden = statuses.length === 0;
  for (const st of statuses) {
    const pip = document.createElement('span');
    pip.className = 'pip' + (st.good ? ' good' : '');
    /* The name survives as the tooltip. Nothing on an overlay is hoverable, but
     * it costs nothing and makes the page readable when opened in a browser. */
    pip.title = st.name + (num(st.games) > 0 ? ' — ' + st.games + ' games left' : '');

    const art_box = document.createElement('span');
    art_box.className = 'pip-art';
    if (st.icon) {
      const img = document.createElement('img');
      img.alt = st.name;
      img.src = st.icon;
      art_box.appendChild(img);
    } else {
      /* No art authored yet: its initial, in the pip's own colour. */
      const letter = document.createElement('span');
      letter.className = 'pip-letter';
      letter.textContent = st.letter || st.name.slice(0, 1).toUpperCase();
      art_box.appendChild(letter);
    }
    /* Borrowed stacks wear the clock in the corner (§5.3) — the flag says "this
     * one is going away", and the count is in the tooltip. */
    if (num(st.games) > 0 && art && art.timer) {
      const clock = document.createElement('img');
      clock.className = 'pip-clock';
      clock.alt = '';
      clock.src = art.timer;
      art_box.appendChild(clock);
    }
    pip.appendChild(art_box);

    const count = document.createElement('span');
    count.className = 'pip-count';
    count.textContent = st.stacks;
    pip.appendChild(count);
    box.appendChild(pip);
  }
}

function drawRoad(road) {
  const strip = el('road-strip');
  strip.innerHTML = '';
  /* NO "+N earlier" HEAD ANY MORE. The strip scrolls the whole road instead of
   * trimming it to a count — a stop turned into a number is a stop the viewer
   * cannot see, and the road is the one part of this page that is about where
   * the run has actually been. `dropped` survives in the payload as the safety
   * valve for a run longer than MAX_ROAD, which nothing realistic reaches. */
  if (road.length && num(road[0].dropped) > 0) {
    const more = document.createElement('span');
    more.className = 'dropped';
    more.textContent = '+' + road[0].dropped;
    strip.appendChild(more);
  }
  road.forEach((stop, i) => {
    if (i > 0) {
      const arrow = document.createElement('span');
      arrow.className = 'arrow' + (stop.unreached ? ' dashed' : '');
      arrow.textContent = stop.unreached ? '⇢' : '→';
      strip.appendChild(arrow);
    }
    const box = document.createElement('span');
    box.className = 'stop'
      + (stop.beaten ? ' beaten' : '')
      + (stop.current ? ' current' : '')
      + (stop.amulet ? ' amulet' : '')
      + (stop.unreached ? ' unreached' : '');
    box.title = stop.name;
    const img = document.createElement('img');
    img.alt = stop.name;
    setImg(img, stop.cover);
    box.appendChild(img);
    /* NO VISIT BADGE. A game the run stood on twice is already TWO STOPS on this
     * strip — `_road` emits one per entry in `path_taken`, never a merged one —
     * so a "2" on the second cover was labelling something the strip had already
     * said by drawing it again, and read as though the two visits had been
     * collapsed into one. The payload still carries `visit` for anyone
     * restyling; the road just walks now, so there is room to show the stops
     * themselves. */
    strip.appendChild(box);
  });
  restartScroll('road-scroll');
}

function drawVerdict(state) {
  const v = el('verdict');
  v.hidden = (state !== 'won' && state !== 'lost');
  if (v.hidden) return;
  v.className = 'verdict ' + state;
  v.textContent = state === 'won' ? 'THE AMULET IS YOURS' : 'THE RUN IS OVER';
}

/* Toasts. Events ride along in every payload; the ones already shown are
 * remembered by (timestamp, text) so a heartbeat does not replay them. On the
 * FIRST payload they are all marked seen without being drawn — a page opened
 * mid-run should not fire eight stale notifications at once. */
function drawEvents(events) {
  const ticker = el('ticker');
  for (const ev of events) {
    const key = ev.at + '|' + ev.text;
    if (shownEvents.has(key)) continue;
    shownEvents.add(key);
    if (firstDraw) continue;
    const t = document.createElement('div');
    t.className = 'toast ' + (ev.tone || 'info');
    t.textContent = ev.text;
    ticker.appendChild(t);
    setTimeout(() => {
      t.classList.add('out');
      setTimeout(() => t.remove(), 600);
    }, TOAST_MS);
  }
  /* The set is unbounded otherwise, and this page runs for a whole stream. The
   * payload only ever carries the last handful, so anything older cannot come
   * back and be mistaken for new. */
  if (shownEvents.size > 200) shownEvents = new Set(events.map(e => e.at + '|' + e.text));
}

/* ------------------------------------------------------- the auto-scroll -- */

/* THE SELF-SCROLLING BOXES. A run eight games deep has more goals than fits the
 * card and more road than fits the strip, and a list that silently cuts off is a
 * list that lies. So when the content is bigger than the box it walks: pause at
 * the start, creep along, pause at the end, snap back. Slow enough to read at a
 * glance while doing something else, which is the whole use case.
 *
 * ONE WALKER, BOTH AXES. The checklist scrolls down and the road scrolls right;
 * everything else about them — the pauses, the speed, the edge fades that appear
 * only where content is actually hidden — is the same behaviour, and two copies
 * of this state machine would be two places for it to drift. */
const SCROLL_PAUSE = 2500;
const SCROLL_SPEED = 14;      /* px per second */

const scrollers = {};

function makeScroller(id, axis) {
  scrollers[id] = { axis: axis, phase: 'start', since: performance.now(),
                    pos: 0, last: 0 };
  const box = el(id);
  if (box) { box.scrollTop = 0; box.scrollLeft = 0; }
}

function restartScroll(id) {
  const st = scrollers[id];
  if (!st) return;
  const box = el(id);
  if (box) { box.scrollTop = 0; box.scrollLeft = 0; }
  st.phase = 'start';
  st.since = performance.now();
  st.pos = 0;
}

/* Fade an edge only when something is actually hidden behind it — a fixed mask
 * would fade the first row of a list parked at the start, which is the most
 * important row on the page. */
function setFades(box, room, at, vertical) {
  const a = room > 1 && at > 1 ? '12px' : '0px';
  const b = room > 1 && at < room - 1 ? '12px' : '0px';
  box.style.setProperty(vertical ? '--fade-top' : '--fade-start', a);
  box.style.setProperty(vertical ? '--fade-bot' : '--fade-end', b);
}

function stepOne(id, now) {
  const st = scrollers[id];
  const box = el(id);
  if (!st || !box) return;
  const vertical = st.axis === 'y';
  const room = vertical ? box.scrollHeight - box.clientHeight
                        : box.scrollWidth - box.clientWidth;
  const at = () => vertical ? box.scrollTop : box.scrollLeft;
  if (room <= 1) {
    if (vertical) box.scrollTop = 0; else box.scrollLeft = 0;
    setFades(box, room, 0, vertical);
    return;
  }
  const dt = (now - (st.last || now)) / 1000;
  st.last = now;
  switch (st.phase) {
    case 'start':
      if (now - st.since > SCROLL_PAUSE) { st.phase = 'run'; st.since = now; }
      break;
    case 'run':
      st.pos = Math.min(room, st.pos + SCROLL_SPEED * dt);
      if (vertical) box.scrollTop = st.pos; else box.scrollLeft = st.pos;
      if (st.pos >= room) { st.phase = 'end'; st.since = now; }
      break;
    case 'end':
      if (now - st.since > SCROLL_PAUSE) {
        st.phase = 'start'; st.since = now; st.pos = 0;
        if (vertical) box.scrollTop = 0; else box.scrollLeft = 0;
      }
      break;
  }
  setFades(box, room, at(), vertical);
}

function frame(now) {
  for (const id in scrollers) stepOne(id, now);
  checkStale();
  requestAnimationFrame(frame);
}

/* ------------------------------------------------------------- helpers --- */

function num(v, fallback) { return typeof v === 'number' ? v : (fallback || 0); }

/* An <img> with no `src` at all rather than an empty one: the CSS hides those,
 * where an empty src makes Chromium draw a broken-image glyph. */
function setImg(img, url) {
  if (url) { img.src = url; } else { img.removeAttribute('src'); }
}

function chip(node, show, text) {
  node.hidden = !show;
  if (show) node.textContent = text;
}

/* The two self-scrolling boxes, registered before the first payload lands so
 * `frame` has something to walk from the very first tick. */
makeScroller('goal-scroll', 'y');
makeScroller('road-scroll', 'x');

poll();
setInterval(poll, POLL_MS);
requestAnimationFrame(frame);
