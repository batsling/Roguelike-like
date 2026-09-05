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
  /* What the front line swings for if the next turn resolves as the board
   * stands — the number that makes the checklist urgent. */
  chip(el('incoming'), num(board.incoming) > 0,
    board.incoming + ' incoming');
  chip(el('bodies'), num(board.bodies) > 0,
    board.bodies + (board.bodies === 1 ? ' body' : ' bodies') + ' following');
}

function drawNow(now, run) {
  setImg(el('now-cover'), now.cover);
  el('now-label').textContent = now.playing ? 'Now playing' : 'Standing on';
  el('now-game').textContent = now.game || '—';
  chip(el('attempts'), num(now.attempts) > 0,
    now.attempts + (now.attempts === 1 ? ' attempt' : ' attempts'));
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
  restartScroll();
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
    if (num(stop.visit) > 1) {
      const badge = document.createElement('span');
      badge.className = 'visit';
      badge.textContent = stop.visit;
      box.appendChild(badge);
    }
    strip.appendChild(box);
  });
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

/* THE SCROLLING CHECKLIST. A run eight games deep has more goals than fits the
 * card, and a list that silently cuts off is a list that lies. So when the
 * content is taller than the box it walks: pause at the top, creep down, pause
 * at the bottom, snap back. Slow enough to read at a glance while doing
 * something else, which is the whole use case. */
const SCROLL_PAUSE = 2500;
const SCROLL_SPEED = 14;      /* px per second */
let scrollState = null;

function restartScroll() {
  const box = el('goal-scroll');
  box.scrollTop = 0;
  scrollState = { phase: 'top', since: performance.now(), pos: 0 };
}

/* Fade an edge only when something is actually hidden behind it. */
function setFades(box, room) {
  const top = room > 1 && box.scrollTop > 1 ? '12px' : '0px';
  const bot = room > 1 && box.scrollTop < room - 1 ? '12px' : '0px';
  box.style.setProperty('--fade-top', top);
  box.style.setProperty('--fade-bot', bot);
}

function stepScroll(now) {
  const box = el('goal-scroll');
  const room = box.scrollHeight - box.clientHeight;
  if (!scrollState || room <= 1) { box.scrollTop = 0; setFades(box, room); return; }
  const st = scrollState;
  const dt = (now - (st.last || now)) / 1000;
  st.last = now;
  switch (st.phase) {
    case 'top':
      if (now - st.since > SCROLL_PAUSE) { st.phase = 'down'; st.since = now; }
      break;
    case 'down':
      st.pos = Math.min(room, st.pos + SCROLL_SPEED * dt);
      box.scrollTop = st.pos;
      if (st.pos >= room) { st.phase = 'bottom'; st.since = now; }
      break;
    case 'bottom':
      if (now - st.since > SCROLL_PAUSE) { st.phase = 'top'; st.since = now; st.pos = 0;
        box.scrollTop = 0; }
      break;
  }
  setFades(box, room);
}

function frame(now) {
  stepScroll(now);
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

restartScroll();
poll();
setInterval(poll, POLL_MS);
requestAnimationFrame(frame);
